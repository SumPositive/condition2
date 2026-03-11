// ValueFormatter.swift
// 測定値の数値→表示文字列変換（旧 Global.m strValue() 相当）

import Foundation

enum ValueFormatter {

    /// val が 0 以下なら空文字。decimals > 0 なら小数表示。
    /// - Parameters:
    ///   - val: 内部値（体温・体重・体脂肪は x10 で格納）
    ///   - decimals: 表示する小数点桁数（0=整数、1=小数1桁）
    static func format(_ val: Int, decimals: Int) -> String {
        guard val > 0 else { return "" }
        if decimals <= 0 {
            return "\(val)"
        }
        let pow10 = intPow(10, decimals)
        let intPart = val / pow10
        let decPart = val - intPart * pow10
        if decPart <= 0 {
            switch decimals {
            case 1: return "\(intPart).0"
            case 2: return "\(intPart).00"
            default: return "\(intPart)"
            }
        } else {
            return "\(intPart).\(decPart)"
        }
    }

    private static func intPow(_ base: Int, _ exp: Int) -> Int {
        var result = 1
        for _ in 0..<exp { result *= base }
        return result
    }
}
