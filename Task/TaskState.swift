//
//  TaskState.swift
//  Task
//
//  Created by Hoon H. on 2016/06/26.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Dispatch

public enum TaskError: ErrorType {
    /// You cannot schedule into an already scheduled execution state.
    case alreadyScheduled
    /// You cannot set continuation context of a completed state.
    case alreadyCompleted
    case alreadyGarbaged
}

enum TaskExecutor {
    case immediate
    case queue(dispatch_queue_t)
}


/// Represents logical state of a task.
///
/// A task state is devided into these phases.
///
/// 1. Running with no schduled continuation.
/// 2. Running with a scheduled continuation.
/// 3. Completed. Done or error.
/// 4. Garbage. Execution has been passed to continuation task.
///
/// This struct models that task state in purely functional manner.
///
/// - Note:
///     Maintainers. Please make sure that this has NO side-effect.
///     Every functions must be pure. 
///     Which means you cannot even call `fatalError()`.
///     Also, this state does not deal with concurrency. Do not put 
///     concurrency handling code here.
///
struct TaskState<T> {
    private(set) var execution: ExecutionState<T>

    init() {
        execution = .running(.unscheduled)
    }
    var isUnscheduled: Bool {
        guard let r = running else { return false }
        switch r {
        case .unscheduled:  return true
        case .scheduled(_): return false
        }
    }
    var isRunning: Bool {
        return running != nil 
    }
    var isComplete: Bool {
        return completion != nil
    }
    var running: RunningState<T>? {
        switch execution {
        case .running(let r):   return r
        default:                return nil
        }
    }
    var completion: CompletionState<T>? {
        switch execution {
        case .complete(let c):  return c
        default:                return nil
        }
    }
    mutating func scheduleRunningContinuation(cc: RunningState<T>.Continuation) throws {
        switch execution {
        case .running(let r):
            switch r {
            case .unscheduled:
                execution = .running(.scheduled(cc))

            case .scheduled(_):
                throw TaskError.alreadyScheduled
            }
        case .complete(_):
            throw TaskError.alreadyCompleted
        case .garbage:
            throw TaskError.alreadyGarbaged
        }
    }
    mutating func setComplete(c: CompletionState<T>) {
        execution = .complete(c)
    }
    mutating func setGarbage() {
        execution = .garbage
    }
}
enum ExecutionState<T> {
    case running(RunningState<T>)
    case complete(CompletionState<T>)
    case garbage
}
enum RunningState<T> {
    typealias ContinuationFunction = (CompletionState<T> -> ())
    typealias Continuation = (TaskExecutor, ContinuationFunction)

    case unscheduled
    case scheduled(Continuation)
}
enum CompletionState<T> {
    case done(T)
    case error(ErrorType)

    var result: T? {
        switch self {
        case .done(let v):  return v
        default:            return nil
        }
    }
}






