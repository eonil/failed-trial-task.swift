//
//  main.swift
//  Task
//
//  Created by Hoon H. on 2016/06/26.
//  Copyright © 2016 Eonil. All rights reserved.
//

func XCTAssert(condition: Bool) {
    assert(condition)
}

import Dispatch

do {

    enum E: ErrorType {
        case aaa
    }
    Task(1222)
    .continueOnDone {
        print($0)
        return $0 * 2
    }
    .continueOnDone {
        print($0)
    }

    let t1 = Task(())
    print(t1)
    let t2 = t1.continueOnDone { 111 }
    let t3 = t2.continueOnDone { $0 * 2 }
    t3.continueOnDone { (_: Int) throws -> () in throw E.aaa }
    .continueOnError { (e: ErrorType) throws -> () in print(e) }
}

do {

    let t1 = Task(111)
    let t2 = Task(222)
    let t3 = Task(333)
    Task.waitForAllOf([t1, t2, t3]).continueOnComplete({ (c: CompletionState<[CompletionState<Int>]>) -> CompletionState<()> in
        print(c)
        XCTAssert(c.result != nil)
        XCTAssert(c.result?.count == 3)
        XCTAssert(c.result?[0].result == 111)
        XCTAssert(c.result?[1].result == 222)
        XCTAssert(c.result?[2].result == 333)
        return .done(())
    })
    sleep(1)
}
