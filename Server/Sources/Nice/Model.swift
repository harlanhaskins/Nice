//
//  Model.swift
//  Nice
//
//  Created by Harlan Haskins on 5/18/25.
//

@preconcurrency import SQLite

/// Base protocol for database models using SQLite
/// Provides table name convention and row initialization
protocol Model: Sendable {
    /// Database table name (defaults to lowercase type name)
    static var tableName: String { get }
    /// Initialize model from SQLite row data
    init(_ row: Row)
}

extension Model {
    /// Default table name implementation using lowercase type name
    static var tableName: String {
        _typeName(self, qualified: false).lowercased()
    }
    /// SQLite table reference for queries
    static var table: Table { Table(tableName) }
}
