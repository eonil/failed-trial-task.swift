//
//  Task.swift
//  Task
//
//  Created by Hoon H. on 2016/06/26.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Dispatch
import Foundation

final class TaskController<T> {
    let task: Task<T>
    init() {
        task = Task<T>(state: TaskState<T>())
    }
    func complete(c: CompletionState<T>) throws {
        try task.complete(c)
    }
}

/// A continuable task.
///
/// Task always runs on a designated GCD queue without any extra synchronization.
///
/// All task MUST finish with normal `.done` or `.error` state.
/// It's an error if any task dies with out completion. (will be reported through 
/// `TaskErrorReporting`)
/// This task has no *cancellation* concept. If you want one, you need to define
/// a *cancelled* state in the value parameter.
///
/// You can continue only once from a task. Second continuation request will fail.
final class Task<Result> {
    private typealias ContinuationQueue = dispatch_queue_t
    private typealias ContinuationFunction = (CompletionState<Result> -> ())
    private typealias Continuation = (ContinuationQueue, ContinuationFunction)

    private var state: TaskState<Result>
    private var schedulabilityFlag = AtomicInt32(value: 1)
    private var completeabilityFlag = AtomicInt32(value: 1)

    /// Creates a completed task.
    init(_ result: Result) {
        self.state = TaskState()
        print(self.state)
        state.setComplete(.done(result))
    }
    private init(state: TaskState<Result>) {
        self.state = state
    }
    deinit {
        switch state.execution {
        case .running(let r):
            switch r {
            case .unscheduled:
                // A terminal task. Fine to quit without execution.
                break
            case .scheduled(_):
                TaskFatalErrorReporting.dispatchError(.scheduledTaskDeinitInRunningScheduledState(taskState: state), "Current task dead in running state with scheduled continuation. All tasks must die in non-running state.")
                // Ignore.
            }
        case .complete(let c):
            switch c {
            case .done(_):
                // OK.
                break
            case .error(let e):
                TaskFatalErrorReporting.dispatchError(.scheduledTaskDeinitInCompleteErrorState(taskState: state), "Current task state is complete with an error `\(e)` that must be handled, but not handled actually.")
                // Ignore in production, but it must be handled.
            }
        case .garbage:
            // Determinance should be done on continued tasks.
            // So, it's fine anyway.
            break
        }
    }
    private func complete(c: CompletionState<Result>) throws {
        guard completeabilityFlag.value == 1 else { throw TaskError.alreadyCompleted }
        completeabilityFlag.decrement()
        print(state)
        guard state.isRunning == true else { throw TaskError.alreadyCompleted }
        switch state.execution {
        case .running(let r):
            state.setComplete(c)
            switch r {
            case .unscheduled:
                // This is a terminal task. Finishes at here.
                // Which means this does not become a garbage.
                break

            case .scheduled(let (x, f)):
                /// Copy completion value by assuming transferring it to a different thread.
                x.execute { [weak self, c] in
                    f(c)
                    // Execution continued to next continuation.
                    // Current task becomes a garbage.
                    self?.state.setGarbage()
                }
            }
        case .complete(_):
            throw TaskError.alreadyCompleted
        case .garbage:
            throw TaskError.alreadyGarbaged
        }
    }
    private func completeWithReportingFatalError(c: CompletionState<Result>) {
        do {
            try complete(c)
        }
        catch let e as TaskError {
            TaskFatalErrorReporting.dispatchError(.dueTo(e), "Cannot set continuation task state to completed due to underlying error `\(e)`.")
        }
        catch let e {
            TaskFatalErrorReporting.dispatchError(.dueToUnknownError(e), "Cannot set continuation task state to completed due to unknown underlying error `\(e)`.")
        }
    }
    private func schedule<Derivation>(in executor: TaskExecutor, continuation process: CompletionState<Result> throws -> CompletionState<Derivation>) throws -> Task<Derivation> {
        guard schedulabilityFlag.value == 1 else { throw TaskError.alreadyScheduled }
        schedulabilityFlag.decrement()
        guard state.isUnscheduled == true || state.isComplete == true else { throw TaskError.alreadyScheduled }
        let t = Task<Derivation>(state: TaskState())
        let x = executor
        // Continuation owns the origin.
        // This function is about only continued task.
        // Does not modify origin task at all.
        let f: ContinuationFunction = { [a = self, weak b = t] c in
            guard let b = b else { return }
            // At this point, execution must be `.complete(_)`.
            switch a.state.execution {
            case .running:
                fatalError("A task SHOULD NOT continue without completion.")
            case .complete(let c):
                do {
                    let c1 = try process(c)
                    try b.complete(c1)
                }
                catch let e {
                    b.completeWithReportingFatalError(.error(e))
                }
            case .garbage:
                TaskFatalErrorReporting.dispatchError(.cannotContinueFromGarbagedTask(taskState: a.state), "Cannot continue from a disposed (garbaged) task.")
                // Ignore.
            }
        }

        switch state.execution {
        case .running(let r):
            switch r {
            case .unscheduled:
                // Continues on unscheduled task.
                // Schedule a new continuation.
                do {
                    try state.scheduleRunningContinuation((x,f))
                }
                catch let e {
                    TaskFatalErrorReporting.dispatchError(.cannotScheduleContinuationTo(taskState: state, dueTo: e), "You cannot continue on this task due to an error: `\(e)`.")
                    // Ignore.
                }
                break
            case .scheduled(_):
                TaskFatalErrorReporting.dispatchError(.dueTo(TaskError.alreadyScheduled), "This task already have a schedule continuation task, so you cannot schedule another.")
                // Ignore.
            }
        case .complete(let c):
            // You can continue from a completed task.
            // In that case, continuation will be executed immediately.
            x.execute { [weak self] in
                f(c)
                // Execution continued to next continuation.
                // Current task becomes a garbage.
                self?.state.setGarbage()
            }

        case .garbage:
            TaskFatalErrorReporting.dispatchError(.dueTo(.alreadyGarbaged), "This task already has been garbged, so you cannot schedule another.")
            // Ignore.
        }
        return t
    }
}

extension Task {
    func continueOnComplete<Derivation>(process: CompletionState<Result> throws -> CompletionState<Derivation>) -> Task<Derivation> {
        do {
            return try schedule(in: .immediate, continuation: process)
        }
        catch let e {
            var s = TaskState<Derivation>()
            s.setComplete(.error(e))
            return Task<Derivation>(state: s)
        }
    }
    func continueOnDone<Derivation>(process: Result throws -> Derivation) -> Task<Derivation> {
        return continueOnComplete({ (c: CompletionState<Result>) -> CompletionState<Derivation> in
            switch c {
            case .done(let v):
                do {
                    let v1 = try process(v)
                    return .done(v1)
                }
                catch let e {
                    return .error(e)
                }
            case .error(let e):
                return .error(e)
            }
        })
    }
    func continueOnError(process: ErrorType throws -> Result) -> Task<Result> {
        return continueOnComplete({ (c: CompletionState<Result>) -> CompletionState<Result> in
            switch c {
            case .done(let v):
                return .done(v)
            case .error(let e):
                do {
                    let v = try process(e)
                    return .done(v)
                }
                catch let e {
                    return .error(e)
                }
            }
        })
    }
}

private extension TaskExecutor {
    func execute(f: ()->()) {
        switch self {
        case .immediate:
            f()
        case .queue(let q):
            dispatch_async(q, f)
        }
    }
}

















