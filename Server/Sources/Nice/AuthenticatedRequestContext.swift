//
//  AuthenticatedRequestContext.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Hummingbird
import HummingbirdAuth

/// Request context for endpoints that require an authenticated user
struct AuthenticatedRequestContext: ChildRequestContext {
    var coreContext: CoreRequestContextStorage
    let user: User

    init(context: BasicAuthRequestContext<User>) throws {
        self.coreContext = context.coreContext
        self.user = try context.requireIdentity()
    }
}
