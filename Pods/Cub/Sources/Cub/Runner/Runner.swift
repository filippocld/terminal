//
//  CubRunner.swift
//  Cub
//
//  Created by Louis D'hauwe on 15/10/2016.
//  Copyright © 2016 - 2017 Silver Fox. All rights reserved.
//

import Foundation
import CoreFoundation

public typealias ExternalFunc = ([String: ValueType], _ callback: @escaping (ValueType?) -> Bool) -> Void

precedencegroup Pipe {
	associativity: left
	higherThan: AdditionPrecedence
}

infix operator |> : Pipe

internal func |><A, B, C>(lhs: @escaping (A) -> B,
                       rhs: @escaping (B) -> C) -> (A) -> C {
	return { rhs(lhs($0)) }
}

internal func |><A, B, C>(lhs: @escaping (A) throws -> B,
                 rhs: @escaping (B) throws -> C) -> (A) throws -> C {
	return { try rhs(lhs($0)) }
}


/// Runs through full pipeline, from lexer to interpreter
public class Runner {

	private let logDebug: Bool
	private let logTime: Bool

	private var source: String?

	public var delegate: RunnerDelegate?

	let compiler: BytecodeCompiler
	
	public var executionFinishedCallback: (() -> Void)?

	// MARK: -

	public init(logDebug: Bool = false, logTime: Bool = false) {
		self.logDebug = logDebug
		self.logTime = logTime
		compiler = BytecodeCompiler()
	}
	
	var externalFunctions = [Int: ([String], ExternalFunc)]()
	
	public func registerExternalFunction(name: String, argumentNames: [String], returns: Bool, callback: @escaping ExternalFunc) {

		let prototype = FunctionPrototypeNode(name: name, argumentNames: argumentNames, returns: returns)
		let node = FunctionNode(prototype: prototype, body: BodyNode(nodes: []))
		let id = compiler.getFunctionId(for: node)
		
		externalFunctions[id] = (argumentNames, callback)
	}
	
	public func runSource(at path: String, get varName: String, useStdLib: Bool = true) throws -> ValueType {

		let source = try String(contentsOfFile: path, encoding: .utf8)

		return try run(source, get: varName, useStdLib: useStdLib)
	}

	public func run(_ source: String, get varName: String, useStdLib: Bool = true) throws -> ValueType {

		let bytecode: BytecodeBody

		if useStdLib {

			let stdLib = try StdLib().stdLibCode()

			guard let compiledStdLib = compileLionessSourceCode(stdLib) else {
				throw RunnerError.stdlibFailed
			}

			guard let compiledSource = compileLionessSourceCode(source) else {
				throw RunnerError.runFailed
			}

			bytecode = compiledStdLib + compiledSource

		} else {

			guard let compiledSource = compileLionessSourceCode(source) else {
				throw RunnerError.runFailed
			}

			bytecode = compiledSource

		}

		let executionBytecode = bytecode.map { $0.executionInstruction }

		let interpreter = try BytecodeInterpreter(bytecode: executionBytecode)
		try interpreter.interpret()

		guard let reg = compiler.getCompiledRegister(for: varName) else {
			throw RunnerError.registerNotFound
		}

		do {
			return try interpreter.getRegValue(for: reg)
		} catch {
			throw RunnerError.registerNotFound
		}

	}

	public func runSource(at path: String) throws {

		let source = try String(contentsOfFile: path, encoding: .utf8)

		try run(source)
	}

	public func run(_ source: String) throws {

		let startTime = CFAbsoluteTimeGetCurrent()

		let stdLib = try StdLib().stdLibCode()

		guard let compiledStdLib = compileLionessSourceCode(stdLib) else {
			throw RunnerError.stdlibFailed
		}

		self.source = source

		if logDebug {
			logSourceCode(source)
		}

		guard let compiledSource = compileLionessSourceCode(source) else {
			throw RunnerError.runFailed
		}

		let fullBytecode = compiledStdLib + compiledSource

		let interpretStartTime = CFAbsoluteTimeGetCurrent()

		interpret(fullBytecode)

		if logTime {

			let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

			let interpretTimeElapsed = CFAbsoluteTimeGetCurrent() - interpretStartTime

			log("\nTotal execution time: \(timeElapsed)s")

			log("\nInterpret execution time: \(interpretTimeElapsed)s")

			log("Instructions executed: \(interpreter?.pcTrace.count ?? 0)")

		}

	}

	public func runWithoutStdlib(_ source: String) throws {

		self.source = source

		let startTime = CFAbsoluteTimeGetCurrent()

		if logDebug {
			logSourceCode(source)
		}

		guard let compiledSource = compileLionessSourceCode(source) else {
			throw RunnerError.runFailed
		}

		let fullBytecode = compiledSource

		let interpretStartTime = CFAbsoluteTimeGetCurrent()

		interpret(fullBytecode)

		if logDebug {

			let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
			log("\nTotal execution time: \(timeElapsed)s")

			let interpretTimeElapsed = CFAbsoluteTimeGetCurrent() - interpretStartTime
			log("\nInterpret execution time: \(interpretTimeElapsed)s")

			log("Instructions executed: \(interpreter?.pcTrace.count ?? 0)")

		}

	}

	// MARK: -
	
	func parseAST(_ source: String) -> [ASTNode]? {
		
		guard let ast = (runLexer |> parseTokens)(source) else {
			return nil
		}
		
		return ast
	}
	
	func compileLionessSourceCode(_ source: String) -> BytecodeBody? {

		guard let ast = parseAST(source) else {
			return nil
		}

		guard let bytecode = compileToBytecode(ast: ast) else {
			return nil
		}

		return bytecode

	}

	private func runLionessSourceCode(_ source: String) {

		guard let bytecode = compileLionessSourceCode(source) else {
			return
		}

		interpret(bytecode)

	}

	private func runLexer(withSource source: String) -> [Token] {

		if logDebug {
			logTitle("Start lexer")
		}

		let lexer = Lexer(input: source)
		let tokens = lexer.tokenize()

		if logDebug {

			log("Number of tokens: \(tokens.count)")

			for t in tokens {
				log(t)
			}

		}

		return tokens

	}
	
	// MARK: - Throwing convenience
	
	public func compileToBytecode(_ source: String) throws -> BytecodeBody {
		return try (lexer |> parse |> compile)(source)
	}
	
	func lexer(_ source: String) throws -> [Token] {
		
		let lexer = Lexer(input: source)
		let tokens = lexer.tokenize()
		
		return tokens
	}
	
	func parse(_ tokens: [Token]) throws -> [ASTNode] {
		let parser = Parser(tokens: tokens)
		return try parser.parse()
	}
	
	func compile(_ ast: [ASTNode]) throws -> BytecodeBody {
		return try compiler.compile(ast)
	}
	
	// MARK: -

	private func parseTokens(_ tokens: [Token]) -> [ASTNode]? {

		if logDebug {
			logTitle("Start parser")
		}

		let parser = Parser(tokens: tokens)

		var ast: [ASTNode]? = nil

		do {

			ast = try parser.parse()

			if logDebug {

				log("Parsed AST:")

				if let ast = ast {
					for a in ast {
						log(a.description)
					}
				}

			}

			return ast

		} catch {

			if logDebug {
				log(error)
			}

			return nil

		}

	}

	private func compileToBytecode(ast: [ASTNode]) -> BytecodeBody? {

		if logDebug {
			logTitle("Start bytecode compiler")
		}

		do {

			let bytecode = try compiler.compile(ast)

			if logDebug {
				logBytecode(bytecode)
			}

			return bytecode

		} catch {

			if logDebug {

				log(error)

			}

			return nil

		}

	}

	var interpreter: BytecodeInterpreter?

	private func interpret(_ bytecode: BytecodeBody) {

		if logDebug {
			logTitle("Start bytecode interpreter")
		}

		do {

			let executionBytecode = bytecode.map { $0.executionInstruction }

			let interpreter = try BytecodeInterpreter(bytecode: executionBytecode)

			for (id, callback) in externalFunctions {
				interpreter.registerExternalFunction(id: id, callback: callback)
			}
			
			interpreter.executionFinishedCallback = executionFinishedCallback
			
			self.interpreter = interpreter

			try interpreter.interpret()

			if logDebug {
				logInterpreter(interpreter)
			}

		} catch {

			if logDebug {

				log("pc trace:")

				if let interpreter = interpreter {
					for pc in interpreter.pcTrace {
						log(bytecode[pc].description)
					}
				}

				log("\n")

				log(error)

			}

		}

	}

	// MARK: -
	// MARK: Logging

	private func logInterpreter(_ interpreter: BytecodeInterpreter) {

		log("Stack at end of execution:\n\(interpreter.stack)\n")

		log("Registers at end of execution:")

		logRegisters(interpreter)

	}

	private func logRegisters(_ interpreter: BytecodeInterpreter) {

		for (key, value) in interpreter.registers {

			if let compiledKey = interpreter.regName(for: key),
				let varName = compiler.getDecompiledVarName(for: compiledKey) {

				log("\(varName) (\(key)) = \(value.description(with: compiler))")

			} else {

				log("\(key) = \(value)")

			}

		}

	}

	private func logSourceCode(_ source: String) {

		logTitle("Source code")

		for s in source.components(separatedBy: "\n") {
			log(s)
		}

	}

	private func logTitle(_ title: String) {

		log("================================")
		log(title)
		log("================================\n")

	}

	private func logBytecode(_ bytecode: BytecodeBody) {

		let bytecodeDescriptor = BytecodeDescriptor(bytecode: bytecode)
		
		log(bytecodeDescriptor.humanReadableDescription())

	}

	private func log(_ message: String) {
		delegate?.log(message)
	}

	private func log(_ error: Error) {

		guard let source = source else {
			delegate?.log(error)
			return
		}

		if let parseError = error as? ParseError {

			let errorDescription = parseError.description(inSource: source)
			delegate?.log(errorDescription)

		} else {

			delegate?.log(error)

		}

	}

	private func log(_ token: Token) {
		delegate?.log(token)
	}

}
