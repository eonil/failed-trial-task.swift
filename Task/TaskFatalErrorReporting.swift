//
//  TaskFatalErrorReporting.swift
//  Task
//
//  Created by Hoon H. on 2016/06/26.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Dispatch

public struct TaskFatalError {
    var state: TaskFatalErrorState
    var message: String
}
public enum TaskFatalErrorState: ErrorType {
    case scheduledTaskDeinitInRunningScheduledState(taskState: Any)
    case scheduledTaskDeinitInCompleteErrorState(taskState: Any)
    case dueTo(TaskError)
    case dueToUnknownError(ErrorType)
    case cannotContinueFromGarbagedTask(taskState: Any)
    case cannotScheduleContinuationTo(taskState: Any, dueTo: ErrorType)
}

/// Reports serious errors occured but couldn't be handled gracefully.
/// Sometimes, even fatal errors shouldn't crash the app in production environment.
/// This object provide last resort for such critical errors.
/// This reporter keeps a dedicated serial queue, and dispatch event on the queue.
public final class TaskFatalErrorReporting {
    private static let gcdq = dispatch_queue_create("TaskErrorReporter/GCDQ", DISPATCH_QUEUE_SERIAL)!
    public static var delegate: (TaskFatalError -> ()) = { assert(false, "A serious error `\($0)` occured, but couldn't be handled gracefully.") }
    static func dispatchError(s: TaskFatalErrorState, _ m: String) {
        dispatch_async(gcdq) {
            let e = TaskFatalError(state: s, message: m)
            TaskFatalErrorReporting.delegate(e)
        }
    }
}

