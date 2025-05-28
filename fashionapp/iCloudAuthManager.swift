import Foundation
import CloudKit
import Combine

class iCloudAuthManager: ObservableObject {
    enum AuthState {
        case unknown, checking, available, unavailable(Error?)
    }

    @Published var state: AuthState = .unknown

    private var cancellables = Set<AnyCancellable>()

    init() {
        checkiCloudStatus()
    }

    func checkiCloudStatus() {
        state = .checking
        CKContainer.default().accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    self?.state = .available
                case .noAccount, .restricted, .couldNotDetermine:
                    self?.state = .unavailable(error)
                @unknown default:
                    self?.state = .unavailable(error)
                }
            }
        }
    }
} 