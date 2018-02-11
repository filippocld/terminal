//
//  AssignmentNode.swift
//  Cub
//
//  Created by Louis D'hauwe on 10/10/2016.
//  Copyright © 2016 - 2017 Silver Fox. All rights reserved.
//

import Foundation

struct AssignmentNodeValidationError: Error {
	let invalidValueType: String
}

public struct AssignmentNode: ASTNode {

	public let variable: ASTNode
	public let value: ASTNode

	public init(variable: ASTNode, value: ASTNode) throws {

		guard value is NumberNode || value is VariableNode || value is StructMemberNode || value is CallNode || value is BinaryOpNode || value is StringNode else {
			throw AssignmentNodeValidationError(invalidValueType: value.description)
		}

		self.variable = variable
		self.value = value
	}

	public func compile(with ctx: BytecodeCompiler, in parent: ASTNode?) throws -> BytecodeBody {

		let v = try value.compile(with: ctx, in: self)

		var bytecode = BytecodeBody()

		bytecode.append(contentsOf: v)

		let label = ctx.nextIndexLabel()

		if let variable = variable as? VariableNode {

			let (varReg, isNew) = ctx.getRegister(for: variable.name)

			let type: BytecodeInstructionType = isNew ? .registerStore : .registerUpdate

			let instruction = BytecodeInstruction(label: label, type: type, arguments: [.index(varReg)], comment: "\(variable.name)")

			bytecode.append(instruction)

		} else if let member = variable as? StructMemberNode {

			let (members, varNode) = try getStructUpdate(member, members: [], with: ctx)

			let (varReg, isNew) = ctx.getRegister(for: varNode.name)

			guard !isNew else {
				throw CompileError.unexpectedCommand
			}

			let varInstructions = try varNode.compile(with: ctx, in: self)
			bytecode.append(contentsOf: varInstructions)

			let membersMapped = members.map { InstructionArgumentType.index($0) }

			let instruction = BytecodeInstruction(label: label, type: .structUpdate, arguments: membersMapped, comment: "\(membersMapped)")

			bytecode.append(instruction)

			let storeInstruction = BytecodeInstruction(label: label, type: .registerUpdate, arguments: [.index(varReg)], comment: "\(varNode.name)")

			bytecode.append(storeInstruction)

		}

		return bytecode

	}

	private func getStructUpdate(_ memberNode: StructMemberNode, members: [Int], with ctx: BytecodeCompiler) throws -> ([Int], VariableNode) {

		var members = members

		guard let memberId = ctx.getStructMemberId(for: memberNode.name) else {
			throw CompileError.unexpectedCommand
		}

		members.append(memberId)

		if let varNode = memberNode.variable as? VariableNode {
			return (members, varNode)

		} else {

			guard let childMemberNode = memberNode.variable as? StructMemberNode else {
				throw CompileError.unexpectedCommand
			}

			return try getStructUpdate(childMemberNode, members: members, with: ctx)

		}

	}

	public var childNodes: [ASTNode] {
		return [variable, value]
	}

	public var description: String {
		return "\(variable.description) = \(value.description)"
	}

	public var nodeDescription: String? {
		return "="
	}

	public var descriptionChildNodes: [ASTChildNode] {
		let lhs = ASTChildNode(connectionToParent: "lhs", node: variable)
		let rhs = ASTChildNode(connectionToParent: "rhs", node: value)

		return [lhs, rhs]
	}

}
