import AppKit

final class PermissionAuthorizationWindowController: NSWindowController, NSWindowDelegate {
  private let appModel: AppModel
  private let localizer: AppLocalizer
  private let permissionService: PermissionAuthorizationService
  private let contentStack = NSStackView()
  private let permissionStack = NSStackView()
  private let confirmButton = NSButton()
  private var displayedPermissions: [AppPermissionRequirement] = []
  private var refreshTimer: Timer?

  init(
    appModel: AppModel,
    localizer: AppLocalizer,
    permissionService: PermissionAuthorizationService
  ) {
    self.appModel = appModel
    self.localizer = localizer
    self.permissionService = permissionService
    super.init(window: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var isVisible: Bool {
    window?.isVisible == true
  }

  func show() {
    if window == nil {
      makeWindow()
    }

    refreshPermissions()
    window?.center()
    window?.delegate = self
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    startRefreshTimer()
  }

  func windowWillClose(_ notification: Notification) {
    stopRefreshTimer()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    NSApplication.shared.terminate(nil)
    return false
  }

  private func makeWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = localizer.text("permission.window.title")
    window.delegate = self
    window.isReleasedWhenClosed = false

    let rootView = NSView()
    rootView.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = rootView

    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 16
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    rootView.addSubview(contentStack)

    let titleLabel = label(localizer.text("permission.window.heading"), font: .boldSystemFont(ofSize: 18))
    let messageLabel = label(localizer.text("permission.window.message"), font: .systemFont(ofSize: 13))
    messageLabel.maximumNumberOfLines = 0

    permissionStack.orientation = .vertical
    permissionStack.alignment = .leading
    permissionStack.spacing = 10

    let buttonStack = NSStackView()
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.spacing = 10
    buttonStack.translatesAutoresizingMaskIntoConstraints = false

    let quitButton = NSButton(
      title: localizer.text("permission.window.quit"),
      target: self,
      action: #selector(quit)
    )
    quitButton.bezelStyle = .rounded

    confirmButton.title = localizer.text("permission.window.confirm")
    confirmButton.target = self
    confirmButton.action = #selector(confirm)
    confirmButton.bezelStyle = .rounded
    confirmButton.keyEquivalent = "\r"
    confirmButton.isEnabled = false

    buttonStack.addArrangedSubview(NSView())
    buttonStack.addArrangedSubview(quitButton)
    buttonStack.addArrangedSubview(confirmButton)

    contentStack.addArrangedSubview(titleLabel)
    contentStack.addArrangedSubview(messageLabel)
    contentStack.addArrangedSubview(permissionStack)
    contentStack.addArrangedSubview(buttonStack)

    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
      contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
      contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
      contentStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -20),
      buttonStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
    ])

    self.window = window
  }

  private func label(_ text: String, font: NSFont) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = .labelColor
    label.lineBreakMode = .byWordWrapping
    return label
  }

  private func refreshPermissions() {
    for permission in permissionService.missingPermissions() where !displayedPermissions.contains(permission) {
      displayedPermissions.append(permission)
    }

    let allGranted = displayedPermissions.allSatisfy {
      permissionService.isGranted($0)
    }
    confirmButton.isEnabled = !displayedPermissions.isEmpty && allGranted

    permissionStack.arrangedSubviews.forEach { view in
      permissionStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }

    if displayedPermissions.isEmpty {
      permissionStack.addArrangedSubview(permissionRow(
        title: localizer.text("permission.window.all_granted"),
        isGranted: true,
        action: nil
      ))
      return
    }

    for permission in displayedPermissions {
      let isGranted = permissionService.isGranted(permission)
      permissionStack.addArrangedSubview(permissionRow(
        title: permission.title(localizer: localizer),
        isGranted: isGranted,
        action: isGranted ? nil : { [weak self] in
          self?.request(permission)
        }
      ))
    }
  }

  private func permissionRow(title: String, isGranted: Bool, action: (() -> Void)?) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = label(title, font: .systemFont(ofSize: 14))
    let statusLabel = label(
      isGranted ? localizer.text("permission.window.status_granted") : localizer.text("permission.window.status_needed"),
      font: .systemFont(ofSize: 12)
    )
    statusLabel.textColor = isGranted ? .systemGreen : .secondaryLabelColor

    let textStack = NSStackView()
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2
    textStack.addArrangedSubview(titleLabel)
    textStack.addArrangedSubview(statusLabel)

    row.addArrangedSubview(textStack)
    row.addArrangedSubview(NSView())

    if let action {
      let button = PermissionActionButton(title: localizer.text("permission.window.authorize"), action: action)
      button.bezelStyle = .rounded
      row.addArrangedSubview(button)
    }

    row.widthAnchor.constraint(equalToConstant: 412).isActive = true
    return row
  }

  private func request(_ permission: AppPermissionRequirement) {
    switch permission {
    case .accessibility:
      appModel.requestAccessibility()
      appModel.openAccessibilitySettings()
      refreshPermissions()
    case .automation(let player):
      DispatchQueue.global(qos: .userInitiated).async {
        PermissionAuthorizationService.requestAutomationPermission(for: player)

        DispatchQueue.main.async { [weak self] in
          self?.refreshPermissions()
        }
      }
    }
  }

  private func startRefreshTimer() {
    guard refreshTimer == nil else {
      return
    }

    refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshPermissions()
    }
  }

  private func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }

  @objc private func confirm() {
    guard permissionService.missingPermissions().isEmpty else {
      refreshPermissions()
      return
    }

    stopRefreshTimer()
    appModel.refresh()
    window?.delegate = nil
    window?.close()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}

private final class PermissionActionButton: NSButton {
  private let actionHandler: () -> Void

  init(title: String, action: @escaping () -> Void) {
    actionHandler = action
    super.init(frame: .zero)
    self.title = title
    target = self
    self.action = #selector(invoke)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc func invoke() {
    actionHandler()
  }
}
