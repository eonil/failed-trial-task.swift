//
//  TaskExtensions.swift
//  Task
//
//  Created by Hoon H. on 2016/06/26.
//  Copyright © 2016 Eonil. All rights reserved.
//

import Dispatch

extension Task {
    /// - Returns:
    ///     Always succeeds.
    static func waitForAllOf(tasks: [Task<Result>]) -> Task<[CompletionState<Result>]> {
        let n = tasks.count
        var a = [CompletionState<Result>]()
        let q = dispatch_queue_create("Task.waitForAll/GCDQ", DISPATCH_QUEUE_SERIAL)!

        let c = TaskController<[CompletionState<Result>]>()
        tasks.forEach { t1 in
            t1.continueOnComplete { [n, q, c] (s: CompletionState<Result>) -> CompletionState<()> in
                dispatch_async(q) {
                    a.append(s)
                    if n == a.count {
                        do {
                            try c.complete(.done(a))
                        }
                        catch let e {
                            do {
                                try c.complete(.error(e))
                            }
                            catch let e1 {
                                assert(false, "Cannot set error `\(e)` due to error `\(e1).")
                            }
                        }
                    }
                }
                return CompletionState.done(())
            }
        }
        return c.task
    }
}