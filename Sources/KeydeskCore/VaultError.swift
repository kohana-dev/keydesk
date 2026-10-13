import Foundation

public enum VaultError: Error, LocalizedError {
    case invalidData, invalidRecoveryKey, unsupportedFormat, staleRevision, locked, unsafeEnvironment, accessDenied
    public var errorDescription: String? {
        switch self {
        case .invalidData: L10n.tr("금고 또는 입력 데이터가 유효하지 않습니다.", "The vault or input data is invalid.")
        case .invalidRecoveryKey: L10n.tr("복구 키가 잘못되었거나 백업이 손상되었습니다.", "The recovery key is incorrect or the backup is damaged.")
        case .unsupportedFormat: L10n.tr("지원하지 않는 금고 형식입니다.", "This vault format is not supported.")
        case .staleRevision: L10n.tr("금고 파일이 변경되었습니다. 다시 열어 주세요.", "The vault file has changed. Open it again.")
        case .locked: L10n.tr("금고가 잠겨 있습니다.", "The vault is locked.")
        case .unsafeEnvironment: L10n.tr("실행 설정을 바꾸는 예약 변수 또는 유효하지 않은 값은 주입할 수 없습니다.", "Reserved variables that change execution settings and invalid values cannot be injected.")
        case .accessDenied: L10n.tr("허용되지 않거나 만료된 작업입니다.", "This operation is not permitted or its approval has expired.")
        }
    }
}
