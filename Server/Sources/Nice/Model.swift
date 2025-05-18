//
//  Model.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

@preconcurrency import SQLite

protocol Model: Sendable {
    static var tableName: String { get }
    init(_ row: Row)
}

extension Model {
    static var tableName: String {
        _typeName(self, qualified: false).lowercased()
    }
    static var table: Table { Table(tableName) }
}
