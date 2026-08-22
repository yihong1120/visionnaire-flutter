import AVFoundation
import AVKit
import Flutter
import UIKit

final class NativeHlsPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return NativeHlsPlayerView(frame: frame, arguments: args)
  }
}

final class NativeHlsPlayerView: NSObject, FlutterPlatformView {
  private let containerView: NativeHlsPlayerContainerView
  private let playerViewController = AVPlayerViewController()
  private var player: AVPlayer?
  private var loadGeneration = 0
  private weak var parentViewController: UIViewController?

  init(frame: CGRect, arguments args: Any?) {
    containerView = NativeHlsPlayerContainerView(frame: frame)
    containerView.backgroundColor = .black
    super.init()
    configurePlayerViewController(arguments: args)
    embedPlayerView()
    configureAudioSession()
    configurePlayer(arguments: args)
  }

  deinit {
    loadGeneration += 1
    player?.pause()
    playerViewController.player = nil
    detachPlayerViewController()
  }

  func view() -> UIView {
    return containerView
  }

  private func configurePlayerViewController(arguments args: Any?) {
    let params = args as? [String: Any]
    let showControls = params?["showControls"] as? Bool ?? true
    playerViewController.showsPlaybackControls = showControls
    playerViewController.allowsPictureInPicturePlayback = showControls
    playerViewController.videoGravity = .resizeAspect
    playerViewController.entersFullScreenWhenPlaybackBegins = false
    playerViewController.exitsFullScreenWhenPlaybackEnds = true
    if #available(iOS 14.2, *) {
      playerViewController.canStartPictureInPictureAutomaticallyFromInline = false
    }
  }

  private func embedPlayerView() {
    let playerView = playerViewController.view!
    playerView.backgroundColor = .black
    playerView.frame = containerView.bounds
    playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    containerView.addSubview(playerView)
    containerView.onMoveToWindow = { [weak self] in
      self?.attachPlayerViewControllerIfNeeded()
    }
  }

  private func attachPlayerViewControllerIfNeeded() {
    guard playerViewController.parent == nil else { return }
    guard let parent = containerView.nearestViewController else { return }
    parent.addChild(playerViewController)
    playerViewController.didMove(toParent: parent)
    parentViewController = parent
  }

  private func detachPlayerViewController() {
    guard playerViewController.parent != nil else { return }
    playerViewController.willMove(toParent: nil)
    playerViewController.removeFromParent()
    parentViewController = nil
  }

  private func configurePlayer(arguments args: Any?) {
    guard
      let params = args as? [String: Any],
      let urlText = params["url"] as? String,
      let url = URL(string: urlText)
    else {
      return
    }

    var options: [String: Any] = [:]
    if let headers = params["headers"] as? [String: String], !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }

    loadGeneration += 1
    let generation = loadGeneration
    let asset = AVURLAsset(url: url, options: options)
    let assetKeys = ["playable"]
    asset.loadValuesAsynchronously(forKeys: assetKeys) { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, self.loadGeneration == generation else {
          return
        }

        var playableError: NSError?
        let playableStatus = asset.statusOfValue(forKey: "playable", error: &playableError)
        guard playableStatus == .loaded && asset.isPlayable else {
          return
        }

        let item = AVPlayerItem(
          asset: asset,
          automaticallyLoadedAssetKeys: assetKeys
        )
        item.preferredForwardBufferDuration = 3
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.isMuted = params["muted"] as? Bool ?? false
        nextPlayer.actionAtItemEnd = .none
        nextPlayer.automaticallyWaitsToMinimizeStalling = true
        nextPlayer.allowsExternalPlayback = false
        if #available(iOS 14.0, *) {
          nextPlayer.audiovisualBackgroundPlaybackPolicy = .pauses
        }

        self.player?.pause()
        self.player = nextPlayer
        self.playerViewController.player = nextPlayer
        nextPlayer.play()
      }
    }
  }

  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.mixWithOthers]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // Playback still works without an active session; PiP may be unavailable.
    }
  }
}

private final class NativeHlsPlayerContainerView: UIView {
  var onMoveToWindow: (() -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onMoveToWindow?()
  }
}

private extension UIView {
  var nearestViewController: UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let viewController = current as? UIViewController {
        return viewController
      }
      responder = current.next
    }
    return nil
  }
}
