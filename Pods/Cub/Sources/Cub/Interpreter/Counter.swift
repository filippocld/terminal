//
//  Counter.swift
//  Cub
//
//  Created by Louis D'hauwe on 26/03/2017.
//  Copyright © 2017 Silver Fox. All rights reserved.
//

import Foundation

struct Counter {

	private var i: UInt

	init(start: UInt = 0) {
		i = start
	}

	var value: Int {
		return Int(i)
	}

	mutating func increment() {
		i += 1
	}

	mutating func decrement() throws {

		guard i > 0 else {
			throw InterpreterError.underflow
		}

		i -= 1
	}

}
