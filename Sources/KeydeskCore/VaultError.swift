import Foundation

public enum VaultError: Error, LocalizedError {
    case invalidData, invalidRecoveryKey, unsupportedFormat, staleRevision, locked, unsafeEnvironment, accessDenied
    public var errorDescription: String? {
        switch self {
        case .invalidData: "금고 또는 입력 데이터가 유효하지 않습니다."
        case .invalidRecoveryKey: "복구 키가 잘못되었거나 백업이 손상되었습니다."
        case .unsupportedFormat: "지원하지 않는 금고 형식입니다."
        case .staleRevision: "금고 파일이 변경되었습니다. 다시 열어 주세요."
        case .locked: "금고가 잠겨 있습니다."
        case .unsafeEnvironment: "실행 설정을 바꾸는 예약 변수 또는 유효하지 않은 값은 주입할 수 없습니다."
        case .accessDenied: "허용되지 않거나 만료된 작업입니다."
        }
    }
}
