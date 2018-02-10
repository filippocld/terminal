//
//  Parser.swift
//  Cub
//
//  Created by Louis D'hauwe on 04/10/2016.
//  Copyright © 2016 - 2017 Silver Fox. All rights reserved.
//

import Foundation

public class Parser {

	private let tokens: [Token]

	/// Token index
	private var index = 0

	public init(tokens: [Token]) {

		self.tokens = tokens.filter {
			if case .comment = $0.type {
				return false
			}

			return true
		}

	}

	// MARK: - Public

	public func parse() throws -> [ASTNode] {

		index = 0

		var nodes = [ASTNode]()

		while index < tokens.count {

			if shouldParseAssignment() {

				let assign = try parseAssignment()
				nodes.append(assign)

			} else {

				let expr = try parseExpression()
				nodes.append(expr)

			}

		}

//		nodes.sort { (node1, node2) -> Bool in
//			
//			if node1 is FunctionNode || node2 is FunctionNode {
//				return true
//			}
//			
//			return false
//		}

		return nodes
	}

	// MARK: - Private

	// TODO: Refactor operators and their precedence

	private let operatorPrecedence: [String : Int] = [
		"+": 20,
		"-": 20,
		"*": 40,
		"/": 40,
		"^": 60
	]

	private func operatorString(for tokenType: TokenType) -> String? {

		if case let .other(op) = tokenType {
			return op
		}

		if case .comparatorEqual = tokenType {
			return "=="
		}

		if case .notEqual = tokenType {
			return "!="
		}

		if case .comparatorLessThan = tokenType {
			return "<"
		}

		if case .comparatorLessThanEqual = tokenType {
			return "<="
		}

		if case .comparatorGreaterThan = tokenType {
			return ">"
		}

		if case .comparatorGreaterThanEqual = tokenType {
			return ">="
		}

		if case .booleanOr = tokenType {
			return "||"
		}

		if case .booleanAnd = tokenType {
			return "&&"
		}

		if case .booleanNot = tokenType {
			return "!"
		}

		if case .comparatorEqual = tokenType {
			return "=="
		}

		if case .notEqual = tokenType {
			return "!="
		}

		return nil
	}

	private func operatorPrecedence(for tokenType: TokenType) -> Int? {

		if case let .other(op) = tokenType {
			return operatorPrecedence[op]
		}

		if case .comparatorEqual = tokenType {
			return 10
		}

		if case .notEqual = tokenType {
			return 10
		}

		if case .comparatorLessThan = tokenType {
			return 10
		}

		if case .comparatorLessThanEqual = tokenType {
			return 10
		}

		if case .comparatorGreaterThan = tokenType {
			return 10
		}

		if case .comparatorGreaterThanEqual = tokenType {
			return 10
		}

		if case .booleanOr = tokenType {
			return 2
		}

		if case .booleanAnd = tokenType {
			return 4
		}

		if case .booleanNot = tokenType {
			return 80
		}

		if case .comparatorEqual = tokenType {
			return 10
		}

		if case .notEqual = tokenType {
			return 10
		}

		return nil
	}

	/// Get operator for token (e.g. '+=' returns '+')
	private func getOperator(forShortHandToken tokenType: TokenType) -> String? {

		if case .shortHandAdd = tokenType {
			return "+"
		}

		if case .shortHandSub = tokenType {
			return "-"
		}

		if case .shortHandMul = tokenType {
			return "*"
		}

		if case .shortHandDiv = tokenType {
			return "/"
		}

		if case .shortHandPow = tokenType {
			return "^"
		}

		return nil
	}

	// MARK: - Token peek & pop

	private func peekPreviousToken() -> Token? {
		return peekToken(offset: -1)
	}

	private func peekCurrentToken() -> Token? {
		return peekToken(offset: 0)
	}

	/// Look ahead 1 token
	private func peekNextToken() -> Token? {
		return peekToken(offset: 1)
	}

	/// Look ahead
	private func peekToken(offset: Int) -> Token? {
		return tokens[safe: index + offset]
	}

	@discardableResult
	private func popCurrentToken() -> Token? {

		guard let t = tokens[safe: index] else {
			return nil
		}

		index += 1

		return t
	}

	@discardableResult
	private func popCurrentToken(andExpect type: TokenType, _ tokenString: String? = nil) throws  -> Token {

		guard let currentToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}

		guard type == currentToken.type else {

			if let tokenString = tokenString {
				throw error(.expectedCharacterButFound(char: tokenString, token: currentToken))
			} else {
				throw error(.unexpectedToken)
			}

		}

		return currentToken

	}

	// MARK: - Parsing look ahead

	/// Look ahead to check if assignment should be parsed
	private func shouldParseAssignment() -> Bool {

		guard let currentToken = peekCurrentToken(), case .identifier = currentToken.type else {
			return false
		}

		var i = 1
		var expectDot = true

		while let nextToken = peekToken(offset: i) {

			if case .equals = nextToken.type {
				return true
			}

			if expectDot {

				guard case .dot = nextToken.type else {
					return false
				}

			} else {

				guard case .identifier = nextToken.type else {
					return false
				}

			}

			expectDot = !expectDot

			i += 1

		}

		return false

	}

	// MARK: - Parsing

	private func parseAssignment() throws -> AssignmentNode {

		guard let currentToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}

		guard case let .identifier(varName) = currentToken.type else {
			throw error(.unexpectedToken)
		}

		let varNode = try parseVariable(with: varName)

		try popCurrentToken(andExpect: .equals, "=")

		let expr = try parseExpression()

		do {
			
			let assign = try AssignmentNode(variable: varNode, value: expr)
			return assign
			
		} catch let error as AssignmentNodeValidationError {
			
			throw self.error(.invalidAssignmentValue(value: error.invalidValueType))
			
		} catch {
		
			throw self.error(.unexpectedToken)

		}
	}

	private func parseNumber() throws -> NumberNode {

		guard let currentToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}

		guard case let .number(value) = currentToken.type else {
			throw error(.unexpectedToken)
		}

		return NumberNode(value: value)
	}
	
	private func parseString() throws -> StringNode {
		
		guard let currentToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}
		
		guard case let .string(value) = currentToken.type else {
			throw error(.unexpectedToken)
		}
		
		return StringNode(value: value)
	}
	
	/// Expression can be a binary/bool op, member
	private func parseExpression() throws -> ASTNode {

		let node = try parsePrimary()

		// Handles short hand operators (e.g. "+=")
		if let currentToken = peekCurrentToken(), let op = getOperator(forShortHandToken: currentToken.type) {

			guard node is VariableNode || node is StructMemberNode else {
				throw error(.expectedVariable)
			}

			popCurrentToken()

			let node1 = try parsePrimary()
			let expr = try parseBinaryOp(node1)

			let operation: BinaryOpNode

			do {
				operation = try BinaryOpNode(op: op, lhs: node, rhs: expr)
			} catch {
				throw self.error(.illegalBinaryOperation, token: currentToken)
			}

			let assignment = try AssignmentNode(variable: node, value: operation)

			return assignment

		}

		let expr = try parseBinaryOp(node)

		return expr

	}

	private func parseParensExpr() throws -> ASTNode {

		try popCurrentToken(andExpect: .parensOpen, "(")

		let expr = try parseExpression()

		try popCurrentToken(andExpect: .parensClose, ")")

		return expr
	}

	private func parseNotOperation() throws -> BinaryOpNode {

		try popCurrentToken(andExpect: .booleanNot, "!")

		guard let currentToken = peekCurrentToken() else {
			throw error(.unexpectedToken)
		}

		if case .parensOpen = currentToken.type {

			let expr = try parseParensExpr()

			return try BinaryOpNode(op: "!", lhs: expr)

		} else {

			let lhs: ASTNode

			switch currentToken.type {

				case .identifier:
					lhs = try parseIdentifier()

				case .number:
					lhs = try parseNumber()

				case .true, .false:
					lhs = try parseRawBoolean()

				default:
					throw error(.unexpectedToken)

			}

			return try BinaryOpNode(op: "!", lhs: lhs)

		}

	}

	private func parseVariable(with name: String) throws -> ASTNode {

		let varNode = VariableNode(name: name)

		if let currentToken = peekCurrentToken(), case .dot = currentToken.type {

			var members = [String]()

			while let currentToken = peekCurrentToken(), case .dot = currentToken.type {

				try popCurrentToken(andExpect: .dot, ".")

				guard let idToken = popCurrentToken() else {
					throw error(.unexpectedToken)
				}

				guard case let .identifier(variable) = idToken.type else {
					throw error(.unexpectedToken)
				}

				members.append(variable)

			}

			var memberNode: StructMemberNode?

			while !members.isEmpty {

				let member = members.removeFirst()

				if let prevMemberNode = memberNode {

					memberNode = StructMemberNode(variable: prevMemberNode, name: member)

				} else {

					memberNode = StructMemberNode(variable: varNode, name: member)

				}

			}

			guard let returnNode = memberNode else {
				throw error(.unexpectedToken)
			}

			return returnNode

		}

		return varNode

	}

	private func parseIdentifier() throws -> ASTNode {

		guard let idToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}

		guard case let .identifier(name) = idToken.type else {
			throw error(.unexpectedToken)
		}

		guard let currentToken = peekCurrentToken(), case .parensOpen = currentToken.type else {
			return try parseVariable(with: name)
		}

		popCurrentToken()

		var arguments = [ASTNode]()

		if let currentToken = peekCurrentToken(), case .parensClose = currentToken.type {

		} else {

			while true {

				let argument = try parseExpression()
				arguments.append(argument)

				if let currentToken = peekCurrentToken(), case .parensClose = currentToken.type {
					break
				}

				guard let commaToken = popCurrentToken() else {
					throw error(.unexpectedToken)
				}

				guard case .comma = commaToken.type else {
					throw error(.expectedArgumentList)
				}

			}

		}

		popCurrentToken()
		return CallNode(callee: name, arguments: arguments)
	}

	/// Primary can be seen as the start of an operation 
	/// (e.g. boolean operation), where this function returns the first term
	private func parsePrimary() throws -> ASTNode {

		guard let currentToken = peekCurrentToken() else {
			throw error(.unexpectedToken)
		}

		switch currentToken.type {
			case .identifier:
				return try parseIdentifier()

			case .number:
				return try parseNumber()
			
			case .string:
				return try parseString()

			case .true, .false:
				return try parseRawBoolean()

			case .booleanNot:
				return try parseNotOperation()

			case .parensOpen:
				return try parseParensExpr()

			case .if:
				return try parseIfStatement()

			case .continue:
				return try parseContinue()

			case .break:
				return try parseBreak()

			case .while:
				return try parseWhileStatement()

			case .return:
				return try parseReturnStatement()

			case .repeat:
				return try parseRepeatWhileStatement()

			case .for:
				return try parseForStatement()

			case .do:
				return try parseDoStatement()

			case .function:
				return try parseFunction()

			case .struct:
				return try parseStruct()

			default:
				throw error(.expectedExpression, token: currentToken)
		}

	}

	private func parseContinue() throws -> ContinueNode {

		try popCurrentToken(andExpect: .continue)

		return ContinueNode()
	}

	private func parseBreak() throws -> BreakLoopNode {

		try popCurrentToken(andExpect: .break)

		return BreakLoopNode()
	}

	private func parseIfStatement() throws -> ConditionalStatementNode {

		try popCurrentToken(andExpect: .if)

		let condition = try parseExpression()

		let body = try parseBodyWithCurlies()

		if let currentToken = peekCurrentToken(), case .else = currentToken.type {

			try popCurrentToken(andExpect: .else)

			if let currentToken = peekCurrentToken(), case .if = currentToken.type {

				let ifStatement = try parseIfStatement()
				let elseBody = BodyNode(nodes: [ifStatement])

				return ConditionalStatementNode(condition: condition, body: body, elseBody: elseBody)

			}

			let elseBody = try parseBodyWithCurlies()

			return ConditionalStatementNode(condition: condition, body: body, elseBody: elseBody)

		} else {

			return ConditionalStatementNode(condition: condition, body: body)

		}

	}

	private func parseDoStatement() throws -> DoStatementNode {

		let doToken = try popCurrentToken(andExpect: .do)

		let amount = try parseExpression()

		try popCurrentToken(andExpect: .times)

		let body = try parseBodyWithCurlies()

		let doStatement: DoStatementNode

		do {

			doStatement = try DoStatementNode(amount: amount, body: body)

		} catch {

			throw self.error(.illegalStatement, token: doToken)

		}

		return doStatement
	}

	private func parseForStatement() throws -> ForStatementNode {

		let forToken = try popCurrentToken(andExpect: .for)

		let assignment = try parseAssignment()

		try popCurrentToken(andExpect: .comma, ",")

		let condition = try parseExpression()

		try popCurrentToken(andExpect: .comma, ",")

		let interval = try parseExpression()

		let body = try parseBodyWithCurlies()

		let forStatement: ForStatementNode

		do {

			forStatement = try ForStatementNode(assignment: assignment, condition: condition, interval: interval, body: body)

		} catch {

			throw self.error(.illegalStatement, token: forToken)

		}

		return forStatement
	}

	private func parseReturnStatement() throws -> ReturnNode {

		try popCurrentToken(andExpect: .return)

		var expr: ASTNode?

		if currentFunctionReturns {

			expr = try parseExpression()

		}

		return ReturnNode(value: expr)
	}

	private func parseWhileStatement() throws -> WhileStatementNode {

		let whileToken = try popCurrentToken(andExpect: .while)

		let condition = try parseExpression()

		let body = try parseBodyWithCurlies()

		let whileStatement: WhileStatementNode

		do {
			whileStatement = try WhileStatementNode(condition: condition, body: body)
		} catch {
			throw self.error(.illegalStatement, token: whileToken)
		}

		return whileStatement
	}

	private func parseRepeatWhileStatement() throws -> RepeatWhileStatementNode {

		try popCurrentToken(andExpect: .repeat)

		let body = try parseBodyWithCurlies()

		let whileToken = try popCurrentToken(andExpect: .while)

		let condition = try parseExpression()

		let whileStatement: RepeatWhileStatementNode

		do {
			whileStatement = try RepeatWhileStatementNode(condition: condition, body: body)
		} catch {
			throw self.error(.illegalStatement, token: whileToken)
		}

		return whileStatement
	}

	private func parseBodyWithCurlies() throws -> BodyNode {

		try popCurrentToken(andExpect: .curlyOpen, "{")

		let body = try parseBody()

		try popCurrentToken(andExpect: .curlyClose, "}")

		return body
	}

	/// Expects opened curly brace, will exit when closing curly brace found
	private func parseBody() throws -> BodyNode {

		var nodes = [ASTNode]()

		while index < tokens.count {

			if let currentToken = peekCurrentToken(), case .curlyClose = currentToken.type {
				break
			}

			if shouldParseAssignment() {

				let assign = try parseAssignment()
				nodes.append(assign)

			} else {

				let expr = try parseExpression()
				nodes.append(expr)

			}

		}

		return BodyNode(nodes: nodes)

	}

	/// Parse "true" or "false"
	private func parseRawBoolean() throws -> BooleanNode {

		guard let currentToken = peekCurrentToken() else {
			throw error(.unexpectedToken)
		}

		if case .true = currentToken.type {
			popCurrentToken()
			return BooleanNode(bool: true)
		}

		if case .false = currentToken.type {
			popCurrentToken()
			return BooleanNode(bool: false)
		}

		throw error(.unexpectedToken)
	}

	private func getCurrentTokenBinaryOpPrecedence() -> Int {

		guard index < tokens.count else {
			return -1
		}

		guard let currentToken = peekCurrentToken() else {
			return -1
		}

		guard let precedence = operatorPrecedence(for: currentToken.type) else {
			return -1
		}

		return precedence
	}

	/// Recursive
	private func parseBinaryOp(_ node: ASTNode, exprPrecedence: Int = 0) throws -> ASTNode {

		var lhs = node

		while true {

			let tokenPrecedence = getCurrentTokenBinaryOpPrecedence()
			if tokenPrecedence < exprPrecedence {
				return lhs
			}

			guard let token = popCurrentToken() else {
				throw error(.unexpectedToken)
			}

			guard let op = operatorString(for: token.type) else {
				throw error(.unexpectedToken)
			}

			var rhs = try parsePrimary()
			let nextPrecedence = getCurrentTokenBinaryOpPrecedence()

			if tokenPrecedence < nextPrecedence {
				rhs = try parseBinaryOp(rhs, exprPrecedence: tokenPrecedence + 1)
			}

			do {
				lhs = try BinaryOpNode(op: op, lhs: lhs, rhs: rhs)
			} catch {
				throw self.error(.illegalBinaryOperation, token: token)
			}

		}

	}

	// MARK: - Functions

	// TODO: use stack once we allow functions in functions
	private var currentFunctionReturns = false

	private func parseFunctionPrototype() throws -> FunctionPrototypeNode {

		guard let idToken = popCurrentToken() else {
			throw error(.unexpectedToken)
		}

		guard case let .identifier(name) = idToken.type else {
			throw error(.expectedFunctionName)
		}

		try popCurrentToken(andExpect: .parensOpen, "(")

		var argumentNames = [String]()
		while let currentToken = peekCurrentToken(), case let .identifier(name) = currentToken.type {
			popCurrentToken()
			argumentNames.append(name)

			if let currentToken = peekCurrentToken(), case .parensClose = currentToken.type {
				break
			}

			guard let commaToken = popCurrentToken() else {
				throw error(.unexpectedToken)
			}

			guard case .comma = commaToken.type else {
				throw error(.expectedArgumentList)
			}
		}

		try popCurrentToken(andExpect: .parensClose, ")")

		var returns = false
		if let type = peekCurrentToken()?.type, type == .returns {
			self.popCurrentToken()
			returns = true
		}

		currentFunctionReturns = returns

		try popCurrentToken(andExpect: .curlyOpen, "{")

		return FunctionPrototypeNode(name: name, argumentNames: argumentNames, returns: returns)
	}

	private func parseFunction() throws -> FunctionNode {

		try popCurrentToken(andExpect: .function)

		let prototype = try parseFunctionPrototype()

		let body = try parseBody()

		try popCurrentToken(andExpect: .curlyClose, "}")

		return FunctionNode(prototype: prototype, body: body)
	}

	private func parseStruct() throws -> StructNode {

		try popCurrentToken(andExpect: .struct)

		guard let idToken = popCurrentToken() else {
			throw error(.expectedFunctionName)
		}

		guard case let .identifier(name) = idToken.type else {
			throw error(.expectedFunctionName)
		}

		try popCurrentToken(andExpect: .curlyOpen, "{")

		var members = [String]()

		while let currentToken = peekCurrentToken(), case let .identifier(name) = currentToken.type {
			popCurrentToken()
			members.append(name)

			if let currentToken = peekCurrentToken(), case .curlyClose = currentToken.type {
				break
			}

			guard let commaToken = popCurrentToken() else {
				throw error(.expectedFunctionName)
			}

			guard case .comma = commaToken.type else {
				throw error(.expectedMemberList)
			}
		}

		let prototype = try StructPrototypeNode(name: name, members: members)

		try popCurrentToken(andExpect: .curlyClose, "}")

		return StructNode(prototype: prototype)
	}

	// MARK: -

	private func error(_ type: ParseErrorType, token: Token? = nil) -> ParseError {

		let token = token ?? peekCurrentToken() ?? peekPreviousToken()
		let range = token?.range

		return ParseError(type: type, range: range)
	}

}
