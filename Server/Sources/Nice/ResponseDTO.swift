//
//  File.swift
//  Nice
//
//  Created by Harlan Haskins on 5/4/25.
//

import Foundation
import Hummingbird
import NiceTypes

protocol ResponseDTO: DTO, ResponseCodable {}

extension CreateUserRequest: ResponseDTO {}
extension Authentication: ResponseDTO {}
extension Location: ResponseDTO {}
extension Forecast: ResponseDTO {}
