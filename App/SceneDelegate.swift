import CloudKit
import UIKit

/// Riceve l'invito CloudKit quando il partner tocca il link (richiede CKSharingSupported = YES).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // App non in esecuzione: i metadata arrivano qui.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { @MainActor in await AppModel.shared.acceptShare(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        // App gia' in esecuzione.
        Task { @MainActor in await AppModel.shared.acceptShare(cloudKitShareMetadata) }
    }
}
