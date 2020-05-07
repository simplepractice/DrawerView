//
//  DrawerView.swift
//  DrawerView
//
//  Created by Mikko Välimäki on 2017-10-28.
//  Copyright © 2017 Mikko Välimäki. All rights reserved.
//

import UIKit
import Dispatch

let LOGGING = false

let dateFormat = "yyyy-MM-dd hh:mm:ss.SSS"
let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = dateFormat
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    return formatter
}()

@objc public enum DrawerPosition: Int {
    case closed = 0
    case collapsed = 1
    case partiallyOpen = 2
    case open = 3
}

@objc public enum DrawerOrientation: Int {
    case bottom = 0
    case left = 1
    case right = 2
    case top = 3
}

extension DrawerPosition: CustomStringConvertible {

    public var description: String {
        switch self {
        case .closed: return "closed"
        case .collapsed: return "collapsed"
        case .partiallyOpen: return "partiallyOpen"
        case .open: return "open"
        }
    }
}

fileprivate extension DrawerPosition {

    static var allPositions: [DrawerPosition] {
        return [.closed, .collapsed, .partiallyOpen, .open]
    }

    static let activePositions: [DrawerPosition] = allPositions
        .filter { $0 != .closed }

    static let openPositions: [DrawerPosition] = [
        .open,
        .partiallyOpen
    ]
}

public class DrawerViewPanGestureRecognizer: UIPanGestureRecognizer {

}

let kVelocityTreshold: CGFloat = 0

let kDefaultCornerRadius: CGFloat = 9.0

let kDefaultShadowRadius: CGFloat = 1.0

let kDefaultShadowOpacity: Float = 0.05

let kLeeway: CGFloat = 10

let kDefaultBackgroundEffect = UIBlurEffect(style: .extraLight)

let kDefaultBorderColor = UIColor(white: 0.2, alpha: 0.2)


@objc public protocol DrawerViewDelegate {

    @objc optional func drawer(_ drawerView: DrawerView, willTransitionFrom startPosition: DrawerPosition, to targetPosition: DrawerPosition)

    @objc optional func drawer(_ drawerView: DrawerView, didTransitionTo position: DrawerPosition)

    @objc optional func drawerDidMove(_ drawerView: DrawerView, drawerOffset: CGFloat)

    @objc optional func drawerWillBeginDragging(_ drawerView: DrawerView)

    @objc optional func drawerWillEndDragging(_ drawerView: DrawerView)

    @objc optional func insetForDrawerView(_ drawerView: DrawerView) -> CGFloat
}

private struct ChildScrollViewInfo {
    var scrollView: UIScrollView
    var scrollWasEnabled: Bool
    var gestureRecognizers: [UIGestureRecognizer] = []
}


@IBDesignable public class DrawerView: UIView {

    // MARK: - Public types

    public enum VisibilityAnimation {
        case none
        case slide
        //case fadeInOut
    }

    public enum InsetAdjustmentBehavior: Equatable {
        /// Evaluate the inset automatically.
        case automatic
        /// Evaluate the inset from superview's safe area.
        case superviewSafeArea
        /// Use fixed inset.
        case fixed(CGFloat)
        /// Ask delegate for a proper inset
        case delegateDriven
        /// Don't use insets.
        case never
    }

    public enum ContentVisibilityBehavior {
        /// Hide any content that gets clipped by the bottom inset.
        case automatic
        /// Same as automatic, but hide only content that is completely below the bottom inset
        case allowPartial
        /// Specify explicit views to hide.
        case custom(() -> [UIView])
        /// Don't use bottom inset.
        case never
    }

    // MARK: - Private properties

    fileprivate var panGestureRecognizer: DrawerViewPanGestureRecognizer!

    fileprivate var overlayTapRecognizer: UITapGestureRecognizer!

    private var panOrigin: CGFloat = 0.0

    private var singleDimensionPanOnly: Bool = true

    private var startedDragging: Bool = false

    private var previousAnimator: UIViewPropertyAnimator? = nil

    private var currentPosition: DrawerPosition = .collapsed

    private var topConstraint: NSLayoutConstraint? = nil

    private var bottomConstraint: NSLayoutConstraint? = nil

    private var leadingConstraint: NSLayoutConstraint? = nil

    private var trailingConstraint: NSLayoutConstraint? = nil

    private var widthConstraint: NSLayoutConstraint? = nil

    private var heightConstraint: NSLayoutConstraint? = nil

    fileprivate var childScrollViews: [ChildScrollViewInfo] = []

    private var overlay: Overlay?

    private let borderView = UIView()

    private let backgroundView = UIVisualEffectView(effect: kDefaultBackgroundEffect)

    private var willConceal: Bool = false

    private var _isConcealed: Bool = false

    private var orientationChanged: Bool = false

    private var lastWarningDate: Date?

    private let embeddedView: UIView?

    private var hiddenChildViews: [UIView]?

    private var orientation: DrawerOrientation = .bottom

    private var isDirectOrientation: Bool {
        switch orientation {
        case .bottom, .right:
            return true
        default:
            return false
        }
    }

    private var isOrientedVertically: Bool {
        switch orientation {
        case .bottom, .top:
            return true
        default:
            return false
        }
    }

    private var marginConstraint: NSLayoutConstraint? {
        switch orientation {
        case .bottom:
            return topConstraint
        case .left:
            return trailingConstraint
        case .right:
            return leadingConstraint
        case .top:
            return bottomConstraint
        }
    }

    private var superviewLength: CGFloat {
        switch orientation {
        case .bottom, .top:
            return superview?.bounds.height ?? 0
        case .left, .right:
            return superview?.bounds.width ?? 0
        }
    }

    private var length: CGFloat {
        switch orientation {
        case .bottom, .top:
            return superview?.bounds.height ?? 0 - variableMargin
        case .left, .right:
            return superview?.bounds.width ?? 0 - variableMargin
        }
    }

    private var sizeConstraint: NSLayoutConstraint? {
        switch orientation {
        case .bottom, .top:
            return heightConstraint
        case .left, .right:
            return widthConstraint
        }
    }

    // MARK: - Visual properties

    /// The corner radius of the drawer view.
    @IBInspectable public var cornerRadius: CGFloat = kDefaultCornerRadius {
        didSet {
            updateVisuals()
        }
    }

    /// The shadow radius of the drawer view.
    @IBInspectable public var shadowRadius: CGFloat = kDefaultShadowRadius {
        didSet {
            updateVisuals()
        }
    }

    /// The shadow opacity of the drawer view.
    @IBInspectable public var shadowOpacity: Float = kDefaultShadowOpacity {
        didSet {
            updateVisuals()
        }
    }

    /// The used effect for the drawer view background. When set to nil no
    /// effect is used.
    public var backgroundEffect: UIVisualEffect? = kDefaultBackgroundEffect {
        didSet {
            updateVisuals()
        }
    }

    public var borderColor: UIColor = kDefaultBorderColor {
        didSet {
            updateVisuals()
        }
    }

    public var insetAdjustmentBehavior: InsetAdjustmentBehavior = .automatic {
        didSet {
            setNeedsLayout()
        }
    }

    public var contentVisibilityBehavior: ContentVisibilityBehavior = .automatic {
        didSet {
            setNeedsLayout()
        }
    }

    public var automaticallyAdjustChildContentInset: Bool = true {
        didSet {
            safeAreaInsetsDidChange()
        }
    }

    public override var isHidden: Bool {
        didSet {
            self.overlay?.isHidden = isHidden
        }
    }

    public var isConcealed: Bool {
        get {
            return _isConcealed
        }
        set {
            setConcealed(newValue, animated: false)
        }
    }

    public func setConcealed(_ concealed: Bool, animated: Bool) {
        _isConcealed = concealed
        setPosition(currentPosition, animated: animated)
    }

    public func removeFromSuperview(animated: Bool) {
        guard let superview = superview else { return }

        let pos = snapPosition(for: .closed, inSuperView: superview)
        self.scrollToPosition(pos, animated: animated, notifyDelegate: true) { _ in
            self.removeFromSuperview()
            self.overlay?.removeFromSuperview()
        }
    }

    // MARK: - Public properties

    @IBOutlet
    public weak var delegate: DrawerViewDelegate?

    /// Boolean indicating whether the drawer is enabled. When disabled, all user
    /// interaction with the drawer is disabled. However, user interaction with the
    /// content is still possible.
    public var enabled: Bool = true

    /// The offset position of the drawer. The offset is measured from the bottom,
    /// zero meaning the top of the drawer is at the bottom of its superview. Hidden
    /// drawers will have the same offset as closed ones do.
    public var drawerOffset: CGFloat {
        guard let superview = superview else {
            return 0
        }

        if self.isConcealed {
            let closedSnapPosition = self.snapPosition(for: .closed, inSuperView: superview)
            return convertScrollPositionToOffset(closedSnapPosition)
        } else {
            return convertScrollPositionToOffset(self.currentSnapPosition)
        }
    }

    // IB support, not intended to be used otherwise.
    @IBOutlet
    public var containerView: UIView? {
        willSet {
            // TODO: Instead, check if has been initialized from nib.
            if self.superview != nil {
                abort(reason: "Superview already set, use normal UIView methods to set up the view hierarcy")
            }
        }
        didSet {
            if let containerView = containerView {
                self.attachTo(view: containerView)
            }
        }
    }

    /// Attaches the drawer to the given view. The drawer will update its constraints
    /// to match the bounds of the target view.
    ///
    /// - parameter view The view to attach to.
    public func attachTo(view: UIView) {
        panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))

        if self.superview == nil {
            self.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(self)
        } else if self.superview !== view {
            log("Invalid state; superview already set when called attachTo(view:)")
        }

        addConstraints(to: view, for: orientation)

        updateVisuals()
    }

    private func addConstraints(to drawer: UIView, for orientation: DrawerOrientation) {
        guard let view = superview else { return }

        var constraints = [NSLayoutConstraint]()

        let setupDefaultLeadingAndTrailingConstraints = { [unowned self] in
            constraints.append(self.leadingAnchor.constraint(equalTo: view.leadingAnchor))
            self.leadingConstraint = constraints.last
            constraints.append(self.trailingAnchor.constraint(equalTo: view.trailingAnchor))
            self.trailingConstraint = constraints.last
        }

        let setupDefaultTopAndBottomConstraints = { [unowned self] in
            constraints.append(self.topAnchor.constraint(equalTo: view.topAnchor))
            self.topConstraint = constraints.last
            constraints.append(self.bottomAnchor.constraint(equalTo: view.bottomAnchor))
            self.bottomConstraint = constraints.last
        }

        switch orientation {
        case .bottom:
            constraints.append(topAnchor.constraint(equalTo: view.topAnchor, constant: length))
            topConstraint = constraints.last

            constraints.append(bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor))
            bottomConstraint = constraints.last

            setupDefaultLeadingAndTrailingConstraints()

            constraints.append(heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 1, constant: -variableMargin))
            heightConstraint = constraints.last
        case .top:
            constraints.append(bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -length))
            bottomConstraint = constraints.last

            constraints.append(topAnchor.constraint(lessThanOrEqualTo: view.topAnchor))
            topConstraint = constraints.last

            setupDefaultLeadingAndTrailingConstraints()

            constraints.append(heightAnchor.constraint(equalTo: view.heightAnchor, constant: -variableMargin))
            heightConstraint = constraints.last
        case .left:
            constraints.append(trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -length))
            trailingConstraint = constraints.last

            constraints.append(leadingAnchor.constraint(lessThanOrEqualTo: view.leadingAnchor))
            leadingConstraint = constraints.last

            setupDefaultTopAndBottomConstraints()

            constraints.append(view.widthAnchor.constraint(equalTo: widthAnchor, constant: -variableMargin))
            widthConstraint = constraints.last
        case .right:
            constraints.append(leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: variableMargin))
            leadingConstraint = constraints.last

            constraints.append(trailingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor))
            trailingConstraint = constraints.last

            setupDefaultTopAndBottomConstraints()

            constraints.append(widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor, multiplier: 1, constant: -variableMargin))
            widthConstraint = constraints.last
        }
        sizeConstraint?.priority = UILayoutPriority(999)
        for constraint in constraints {
            constraint.isActive = true
        }
    }

    // TODO: Use size classes with the positions.

    /// The appropriate variable margin for the drawer when it is at its full height.
    public var variableMargin: CGFloat = 68.0 {
        didSet {
            self.updateSnapPosition(animated: false)
        }
    }

    /// The height or width of the drawer when collapsed.
    public var collapsedDimension: CGFloat = 68.0 {
        didSet {
            self.updateSnapPosition(animated: false)
        }
    }

    /// The height or width of the drawer when partially open.
    public var partiallyOpenDimension: CGFloat = 264.0 {
        didSet {
            self.updateSnapPosition(animated: false)
        }
    }

    /// The current position of the drawer.
    public var position: DrawerPosition {
        get {
            return currentPosition
        }
        set {
            self.setPosition(newValue, animated: false)
        }
    }

    /// List of user interactive positions for the drawer. Please note that
    /// programmatically any position is still possible, this list only
    /// defines the snap positions for the drawer
    public var snapPositions: [DrawerPosition] = DrawerPosition.activePositions {
        didSet {
            if !snapPositions.contains(self.position) {
                // Current position is not in the given list, default to the most closed one.
                self.setInitialPosition()
            }
            self.sizeConstraint?.constant = -variableMargin
        }
    }

    /// An opacity (0 to 1) used for automatically hiding child views. This is made public so that
    /// you can match the opacity with your custom views.
    public private(set) var currentChildOpacity: CGFloat = 1.0

    /// If set, overlay view is shown below the drawer when it's fully opened.
    public var shouldShowOverlay = false

    // MARK: - Initialization

    init() {
        self.embeddedView = nil
        super.init(frame: CGRect())
        self.setup()
    }

    private init(embeddedView: UIView?, orientation: DrawerOrientation) {
        self.orientation = orientation
        self.embeddedView = embeddedView
        super.init(frame: CGRect())
        self.setup()
    }

    override init(frame: CGRect) {
        self.embeddedView = nil
        super.init(frame: frame)
        self.setup()
    }

    required public init?(coder aDecoder: NSCoder) {
        self.embeddedView = nil
        super.init(coder: aDecoder)
        self.setup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Initialize the drawer with contents of the given view. The
    /// provided view is added as a child view for the drawer and
    /// constrained with auto layout from all of its sides.
    convenience public init(withView view: UIView, orientation: DrawerOrientation) {
        self.init(embeddedView: view, orientation: orientation)

        view.frame = self.bounds
        view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(view)

        for c in [
            view.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            view.heightAnchor.constraint(equalTo: self.heightAnchor),
            view.topAnchor.constraint(equalTo: self.topAnchor)
        ] {
            c.isActive = true
        }
    }

    private func setup() {
        #if swift(>=4.2)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
        #else
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChange),
            name: NSNotification.Name.UIDeviceOrientationDidChange,
            object: nil)
        #endif

        panGestureRecognizer = DrawerViewPanGestureRecognizer()
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.minimumNumberOfTouches = 1
        panGestureRecognizer.delegate = self
        self.addGestureRecognizer(panGestureRecognizer)
        self.translatesAutoresizingMaskIntoConstraints = false

        setupBackgroundView()
        setupBorderView()

        updateVisuals()
    }

    private func setupBackgroundView() {
        backgroundView.frame = self.bounds
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.clipsToBounds = true

        self.insertSubview(backgroundView, at: 0)
        addBackgroundConstraints(view: backgroundView, defaultOffset: 0)
        self.backgroundColor = UIColor.clear
    }

    private func setupBorderView() {
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.clipsToBounds = true
        borderView.isUserInteractionEnabled = false
        borderView.backgroundColor = UIColor.clear
        borderView.layer.cornerRadius = 10

        self.addSubview(borderView)
        addBackgroundConstraints(view: borderView, defaultOffset: 0.5)
    }

    @discardableResult
    private func addBackgroundConstraints(view: UIView, defaultOffset: CGFloat = 0, leewayOffset: CGFloat = 10) -> [NSLayoutConstraint] {
        let constraints: [NSLayoutConstraint]
        switch orientation {
        case .bottom:
            constraints = [
                view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -defaultOffset),
                view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: defaultOffset),
                view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: leewayOffset),
                view.topAnchor.constraint(equalTo: self.topAnchor, constant: -defaultOffset)
            ]
        case .top:
            constraints = [
                view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -defaultOffset),
                view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: defaultOffset),
                view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: defaultOffset),
                view.topAnchor.constraint(equalTo: self.topAnchor, constant: -leewayOffset)
            ]
        case .left:
            constraints = [
                view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -defaultOffset),
                view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: leewayOffset),
                view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: defaultOffset),
                view.topAnchor.constraint(equalTo: self.topAnchor, constant: -defaultOffset)
            ]
        case .right:
            constraints = [
                view.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: -leewayOffset),
                view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: defaultOffset),
                view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: defaultOffset),
                view.topAnchor.constraint(equalTo: self.topAnchor, constant: -defaultOffset)
            ]
        }

        for constraint in constraints {
            constraint.isActive = true
        }

        return constraints
    }

    // MARK: - View methods

    public override func layoutSubviews() {
        super.layoutSubviews()

        // NB: For some reason the subviews of the blur
        // background don't keep up with sudden change.
        for view in self.backgroundView.subviews {
            view.frame.origin.y = 0
        }

        if self.orientationChanged {
            self.updateSnapPosition(animated: false)
            self.orientationChanged = false
        }
    }

    @objc func handleOrientationChange() {
        self.orientationChanged = true
        self.setNeedsLayout()
    }

    // MARK: - Scroll position methods

    /// Set the position of the drawer.
    ///
    /// - parameter position The position to be set.
    /// - parameter animated Wheter the change should be animated or not.
    public func setPosition(_ position: DrawerPosition, animated: Bool) {
        guard let superview = self.superview else {
            log("ERROR: Not contained in a view.")
            log("ERROR: Could not evaluate snap position for \(position)")
            return
        }

        //updateBackgroundVisuals(self.backgroundView)
        // Get the next available position. Closed position is always supported.

        // Notify only if position changed.
        let visiblePosition: DrawerPosition = (_isConcealed ? .closed : position)
        // Don't notify about position if concealing the drawer.
        let notifyPosition = !_isConcealed && (currentPosition != visiblePosition)
        if notifyPosition {
            self.delegate?.drawer?(self, willTransitionFrom: currentPosition, to: position)
        }

        self.currentPosition = position

        let nextSnapPosition = snapPosition(for: visiblePosition, inSuperView: superview)
        self.scrollToPosition(nextSnapPosition, animated: animated, notifyDelegate: true) { _ in
            if notifyPosition {
                self.delegate?.drawer?(self, didTransitionTo: visiblePosition)
            }
        }
    }

    private func scrollToPosition(_ scrollPosition: CGFloat, animated: Bool, notifyDelegate: Bool, completion: ((Bool) -> Void)? = nil) {
        if previousAnimator?.isRunning == true {
            previousAnimator?.stopAnimation(false)
            if let s = previousAnimator?.state, s == .stopped {
                previousAnimator?.finishAnimation(at: .current)
            }
            previousAnimator = nil
        }

        if animated {
            // Create the animator.
            let animator = UIViewPropertyAnimator(
                duration: 0.5,
                timingParameters: UISpringTimingParameters(dampingRatio: 0.8))
            animator.addAnimations {
                self.setScrollPosition(scrollPosition, notifyDelegate: notifyDelegate)
            }
            animator.addCompletion({ pos in
                if pos == .end {
                    self.superview?.layoutIfNeeded()
                    self.layoutIfNeeded()
                    self.setNeedsUpdateConstraints()
                } else if pos == .current {
                    // Animation was cancelled, update the constraints to match view's frame.
                    // NOTE: This is a workaround as there seems to be no way of creating
                    // a spring-based animation with .beginFromCurrentState option. Also it
                    // seemded that the option didn't work as expected, so we need to do this
                    // here manually.
                    if let f = self.layer.presentation()?.frame {
                        self.setScrollPosition((self.isOrientedVertically ? f.minY : f.minX), notifyDelegate: false)
                    }
                }

                if let completion = completion {
                    DispatchQueue.main.async {
                        completion(pos == .end)
                    }
                }
            })

            // Add extra height to make sure that bottom doesn't show up.
            self.superview?.layoutIfNeeded()

            animator.startAnimation()
            previousAnimator = animator
        } else {
            self.setScrollPosition(scrollPosition, notifyDelegate: notifyDelegate)
        }
    }

    private func updateScrollPosition(whileDraggingAtPoint dragPoint: CGFloat, notifyDelegate: Bool) {
        guard let superview = superview else {
            log("ERROR: Cannot set position, no superview defined")
            return
        }

        let positions = self.snapPositions
            .compactMap { self.snapPosition(for: $0, inSuperView: superview) }
            .sorted()

        let position: CGFloat
        if let lowerBound = positions.first, dragPoint < lowerBound {
            position = lowerBound - damp(value: lowerBound - dragPoint, factor: 20)
        } else if let upperBound = positions.last, dragPoint > upperBound {
            position = upperBound + damp(value: dragPoint - upperBound, factor: 20)
        } else {
            position = dragPoint
        }

        self.setScrollPosition(position, notifyDelegate: notifyDelegate)
    }

    private func updateSnapPosition(animated: Bool) {
        if panGestureRecognizer.state.isTracking == false {
            self.setPosition(currentPosition, animated: animated)
        }
    }

    private func setScrollPosition(_ scrollPosition: CGFloat, notifyDelegate: Bool) {
        if isDirectOrientation {
            self.marginConstraint?.constant = scrollPosition
        } else {
            self.marginConstraint?.constant = -scrollPosition
        }
        self.setOverlayOpacity(forScrollPosition: scrollPosition)
        self.setShadowOpacity(forScrollPosition: scrollPosition)
        self.setChildrenOpacity(forScrollPosition: scrollPosition)

        if notifyDelegate {
            let drawerOffset = convertScrollPositionToOffset(scrollPosition)
            self.delegate?.drawerDidMove?(self, drawerOffset: drawerOffset)
        }

        self.superview?.layoutIfNeeded()
    }

    private func setInitialPosition() {
        self.position = self.snapPositionsDescending.last ?? .collapsed
    }

    // MARK: - Pan handling

    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {

        let isFullyExpanded = self.snapPositionsDescending.last == self.position

        switch sender.state {
        case .began:
            self.delegate?.drawerWillBeginDragging?(self)

            self.previousAnimator?.stopAnimation(true)

            // Get the actual position of the view.
            let frame = self.layer.presentation()?.frame ?? self.frame
            switch orientation {
            case .bottom, .right:
                panOrigin = isOrientedVertically ? frame.origin.y : frame.origin.x
            default:
                panOrigin = isOrientedVertically ? superviewLength - frame.maxY : superviewLength - frame.maxX
            }
            self.singleDimensionPanOnly = true
            updateScrollPosition(whileDraggingAtPoint: panOrigin, notifyDelegate: true)

        case .changed:

            let translation = sender.translation(in: self)
            let velocity = sender.velocity(in: self)

            let dimensionalVelocity = isOrientedVertically ? velocity.y : velocity.x

            guard dimensionalVelocity != 0 else { break }

            // If scrolling upwards a scroll view, ignore the events.
            if self.childScrollViews.count > 0 {

                // Collect the active pan gestures with their respective scroll views.
                let simultaneousPanGestures = self.childScrollViews
                    .filter { $0.scrollWasEnabled }
                    .flatMap { scrollInfo -> [(pan: UIPanGestureRecognizer, scrollView: UIScrollView)] in
                        // Filter out non-pan gestures
                        scrollInfo.gestureRecognizers.compactMap { recognizer in
                            (recognizer as? UIPanGestureRecognizer).map { ($0, scrollInfo.scrollView) }
                        }
                    }
                    .filter { $0.pan.isActive() }

                // TODO: Better support for scroll views that don't have directional scroll lock enabled.
                let ableToDetermineOppositePan =
                    simultaneousPanGestures.count > 0 && simultaneousPanGestures
                        .allSatisfy { self.ableToDetermineOppositeDirectionPan($0.scrollView) }

                if simultaneousPanGestures.count > 0 && !ableToDetermineOppositePan && shouldWarn(&lastWarningDate) {
                    NSLog("WARNING (DrawerView): One subview of DrawerView has not enabled directional lock. Without directional lock it is ambiguous to determine if DrawerView should start panning.")
                }

                if ableToDetermineOppositePan {
                    let isDirectPan = simultaneousPanGestures.count > 0
                        && simultaneousPanGestures
                            .allSatisfy {
                                let pan = $0.pan.translation(in: self)
                                let isVertical = !(pan.x != 0 && pan.y == 0)
                                let isHorizontal = !(pan.y != 0 && pan.x == 0)
                                return self.isOrientedVertically ? isVertical : isHorizontal
                    }

                    if isDirectPan {
                        self.singleDimensionPanOnly = false
                    }

                    if self.singleDimensionPanOnly {
                        log("Vertical pan cancelled due to direction lock")
                        break
                    }
                }


                let activeScrollViews = simultaneousPanGestures
                    .compactMap { $0.pan.view as? UIScrollView }

                let childReachedTheLimit = activeScrollViews.contains {
                    self.isOrientedVertically ? $0.contentOffset.y <= 0 : $0.contentOffset.x <= 0
                }

                let childScrollEnabled = activeScrollViews.contains { $0.isScrollEnabled }

                let scrollingToBottom = dimensionalVelocity < 0

                let shouldScrollChildView: Bool
                if !childScrollEnabled {
                    shouldScrollChildView = false
                } else if !childReachedTheLimit && !scrollingToBottom {
                    shouldScrollChildView = true
                } else if childReachedTheLimit && !scrollingToBottom {
                    shouldScrollChildView = false
                } else if !isFullyExpanded {
                    shouldScrollChildView = false
                } else {
                    shouldScrollChildView = true
                }

                // Disable child view scrolling
                if !shouldScrollChildView && childScrollEnabled {

                    startedDragging = true

                    sender.setTranslation(CGPoint.zero, in: self)

                    // Scrolling downwards and content was consumed, so disable
                    // child scrolling and catch up with the offset.
                    let frame = self.layer.presentation()?.frame ?? self.frame
                    let minContentOffset = activeScrollViews.map {
                        self.isOrientedVertically ? $0.contentOffset.y : $0.contentOffset.x
                    }.min() ?? 0

                    let baseOrigin = self.isOrientedVertically ? frame.origin.y : frame.origin.x

                    if minContentOffset < 0 {
                        self.panOrigin = baseOrigin - minContentOffset
                    } else {
                        self.panOrigin = baseOrigin
                    }

                    // Also animate to the proper scroll position.
                    log("Animating to target position...")

                    self.previousAnimator?.stopAnimation(true)
                    self.previousAnimator = UIViewPropertyAnimator.runningPropertyAnimator(
                        withDuration: 0.2,
                        delay: 0.0,
                        options: [.allowUserInteraction, .beginFromCurrentState],
                        animations: {
                            // Disabling the scroll removes negative content offset
                            // in the scroll view, so make it animate here.
                            log("Disabled child scrolling")
                            activeScrollViews.forEach { $0.isScrollEnabled = false }
                            let pos = self.panOrigin
                            self.updateScrollPosition(whileDraggingAtPoint: pos, notifyDelegate: true)
                    }, completion: nil)
                } else if !shouldScrollChildView {
                    // Scroll only if we're not scrolling the subviews.
                    startedDragging = true
                    let pos = panOrigin + (isOrientedVertically ? translation.y : translation.x)
                    updateScrollPosition(whileDraggingAtPoint: pos, notifyDelegate: true)
                }
            } else {
                startedDragging = true
                let pos: CGFloat
                switch orientation {
                case .bottom, .right:
                    pos = panOrigin + (isOrientedVertically ? translation.y : translation.x)
                default:
                    pos = panOrigin - (isOrientedVertically ? translation.y : translation.x)
                }
                updateScrollPosition(whileDraggingAtPoint: pos, notifyDelegate: true)
            }

        case.failed:
            log("ERROR: UIPanGestureRecognizer failed")
            fallthrough
        case .ended:
            let velocity = sender.velocity(in: self)
            log("Ending with vertical velocity \(isOrientedVertically ? velocity.y : velocity.x)")

            let activeScrollViews = self.childScrollViews.filter { sv in
                sv.scrollView.isScrollEnabled &&
                    sv.scrollView.gestureRecognizers?.contains { $0.isActive() } ?? false
            }

            if activeScrollViews.contains(where: {
                let offsetPoint = $0.scrollView.contentOffset
                let offsetValue = isOrientedVertically ? offsetPoint.y : offsetPoint.x
                return offsetValue > 0 }) {
                // Let it scroll.
                log("Let child view scroll.")
            } else if startedDragging {
                self.delegate?.drawerWillEndDragging?(self)

                // Check velocity and snap position separately:
                // 1) A treshold for velocity that makes drawer slide to the next state
                // 2) A prediction that estimates the next position based on target offset.
                // If 2 doesn't evaluate to the current position, use that.

                let targetOffset: CGFloat
                let advancement: Int
                if isOrientedVertically {
                    let base = isDirectOrientation ? frame.origin.y : superviewLength - frame.maxY
                    targetOffset = base + velocity.y / 100
                    advancement = velocity.y < 0 ? -1 : 1
                } else {
                    let base = isDirectOrientation ? frame.origin.x : superviewLength - frame.maxX
                    targetOffset = base + velocity.x / 100
                    advancement = velocity.x < 0 ? -1 : 1
                }
                let targetPosition = positionFor(offset: targetOffset)

                // The positions are reversed, reverse the sign.

                let nextPosition: DrawerPosition
                let absVelocity = abs(isOrientedVertically ? velocity.y : velocity.x)
                if targetPosition == self.position && absVelocity > kVelocityTreshold,
                    let advanced = self.snapPositionsDescending.advance(from: targetPosition, offset: advancement) {
                    nextPosition = advanced
                } else {
                    nextPosition = targetPosition
                }
                self.setPosition(nextPosition, animated: true)
            }

            self.childScrollViews.forEach { $0.scrollView.isScrollEnabled = $0.scrollWasEnabled }
            self.childScrollViews = []

            startedDragging = false

        default:
            break
        }
    }

    @objc private func onTapOverlay(_ sender: UITapGestureRecognizer) {
        if sender.state == .ended {

            if let prevPosition = self.snapPositionsDescending.advance(from: self.position, offset: -1) {

                self.delegate?.drawer?(self, willTransitionFrom: currentPosition, to: prevPosition)

                self.setPosition(prevPosition, animated: true)

                self.delegate?.drawer?(self, didTransitionTo: prevPosition)
            }
        }
    }

    // MARK: - Dynamically evaluated properties

    private func snapPositions(for positions: [DrawerPosition], inSuperView superview: UIView)
        -> [(position: DrawerPosition, snapPosition: CGFloat)]  {
            return positions
                // Group the info on position together. For the sake of
                // robustness, hide the ones without snap position.
                .map { p in (
                    position: p,
                    snapPosition: self.snapPosition(for: p, inSuperView: superview)
                    )
            }
    }

    private var inset: CGFloat {
        let result: CGFloat
        switch insetAdjustmentBehavior {
        case .automatic:
            return automaticInset
        case .superviewSafeArea:
            return superviewSafeAreaInset
        case .fixed(let inset):
            result = inset
        case .delegateDriven:
            result = delegate?.insetForDrawerView?(self) ?? 0
        case .never:
            result = 0
        }
        return result
    }

    private var superviewSafeAreaInset: CGFloat {
        guard #available(iOS 11.0, *) else { return 0 }
        switch orientation {
        case .bottom:
            return superview?.safeAreaInsets.bottom ?? 0
        case .top:
            return superview?.safeAreaInsets.top ?? 0
        case .left:
            return superview?.safeAreaInsets.left ?? 0
        case .right:
            return superview?.safeAreaInsets.right ?? 0
        }
    }

    private var automaticInset: CGFloat {
        guard #available(iOS 11.0, *), let window = self.window, let superview = superview else { return 0 }
        let bounds = window.convert(superview.bounds, to: window)
        switch orientation {
        case .bottom:
            return max(0, window.safeAreaInsets.bottom - (window.bounds.maxY - bounds.maxY))
        case .top:
            return max(0, window.safeAreaInsets.top - (bounds.minY - window.bounds.minY))
        case .left:
            return max(0, window.safeAreaInsets.left - (bounds.minX - window.bounds.minX))
        case .right:
            return max(0, window.safeAreaInsets.right - (window.bounds.maxX - bounds.maxX))
        }
    }

    fileprivate func snapPosition(for position: DrawerPosition, inSuperView superview: UIView) -> CGFloat {
        let base = isOrientedVertically ? superview.bounds.height : superview.bounds.width
        switch position {
        case .open:
            return base - inset - self.variableMargin
        case .partiallyOpen:
            return base - inset - self.partiallyOpenDimension
        case .collapsed:
            return base - inset - self.collapsedDimension
        case .closed:
            // When closed, the safe area is ignored since the
            // drawer should not be visible.
            return base
        }
    }

    private func opacityFactor(for position: DrawerPosition) -> CGFloat {
        switch position {
        case .open:
            return 1
        case .partiallyOpen:
            return 0
        case .collapsed:
            return 0
        case .closed:
            return 0
        }
    }

    private func shadowOpacityFactor(for position: DrawerPosition) -> Float {
        switch position {
        case .open:
            return self.shadowOpacity
        case .partiallyOpen:
            return self.shadowOpacity
        case .collapsed:
            return self.shadowOpacity
        case .closed:
            return 0
        }
    }

    private func positionFor(offset: CGFloat) -> DrawerPosition {
        guard let superview = superview else {
            return DrawerPosition.collapsed
        }
        let distances = self.snapPositions
            .compactMap { pos in (pos: pos, y: snapPosition(for: pos, inSuperView: superview)) }
            .sorted { (p1, p2) -> Bool in
                return abs(p1.y - offset) < abs(p2.y - offset)
        }

        return distances.first.map { $0.pos } ?? DrawerPosition.collapsed
    }

    // MARK: - Visuals handling

    private func updateVisuals() {
        updateLayerVisuals(self.layer)
        updateBorderVisuals(self.borderView)
        updateOverlayVisuals(self.overlay)
        updateBackgroundVisuals(self.backgroundView)
        sizeConstraint?.constant = -variableMargin

        self.setNeedsDisplay()
    }

    private func updateLayerVisuals(_ layer: CALayer) {
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity
        layer.cornerRadius = self.cornerRadius
    }

    private func updateBorderVisuals(_ borderView: UIView) {
        borderView.layer.cornerRadius = self.cornerRadius
        borderView.layer.borderColor = self.borderColor.cgColor
        borderView.layer.borderWidth = 0.5
    }

    private func updateOverlayVisuals(_ overlay: Overlay?) {
        overlay?.backgroundColor = UIColor.black
        overlay?.cutCornerSize = self.cornerRadius
    }

    private func updateBackgroundVisuals(_ backgroundView: UIVisualEffectView) {

        backgroundView.effect = self.backgroundEffect
        if #available(iOS 11.0, *) {
            backgroundView.layer.cornerRadius = self.cornerRadius
            switch orientation {
            case .left:
                backgroundView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            case .right:
                backgroundView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            case .bottom:
                backgroundView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            case .top:
                backgroundView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        } else {
            // Fallback on earlier versions
            let mask: CAShapeLayer = {
                let m = CAShapeLayer()
                let frame: CGRect
                let corners: UIRectCorner
                switch orientation {
                    case .left:
                        frame = backgroundView.bounds.insetBy(top: 0, bottom: 0, left: -kLeeway, right: 0)
                        corners = [.topRight, .bottomRight]
                    case .right:
                        frame = backgroundView.bounds.insetBy(top: 0, bottom: 0, left: 0, right: -kLeeway)
                        corners = [.topLeft, .bottomLeft]
                    case .bottom:
                        frame = backgroundView.bounds.insetBy(top: 0, bottom: -kLeeway, left: 0, right: 0)
                        corners = [.topLeft, .topRight]
                    case .top:
                        frame = backgroundView.bounds.insetBy(top: -kLeeway, bottom: 0, left: 0, right: 0)
                        corners = [.bottomLeft, .bottomRight]
                }
                let path = UIBezierPath(roundedRect: frame, byRoundingCorners: corners, cornerRadii: CGSize(width: self.cornerRadius, height: self.cornerRadius))
                m.path = path.cgPath
                return m
            }()
            backgroundView.layer.mask = mask
        }
    }

    private func int(for bool: Bool) -> Int {
        return 50
    }

    public override func safeAreaInsetsDidChange() {
        if automaticallyAdjustChildContentInset {
            let inset = self.inset
            self.adjustChildContentInset(self, inset: inset)
        }
    }

    private func adjustChildContentInset(_ view: UIView, inset: CGFloat) {
        for childView in view.subviews {
            if let scrollView = childView as? UIScrollView {
                // Do not recurse into child views if content
                // inset can be set on the superview.
                let convertedBounds = scrollView.convert(scrollView.bounds, to: self)
                let distanceFromBase: CGFloat
                switch orientation {
                case .bottom:
                    distanceFromBase = self.bounds.height - convertedBounds.maxY
                case .top:
                    distanceFromBase = self.bounds.height - convertedBounds.minY
                case .right:
                    distanceFromBase = self.bounds.width - convertedBounds.maxX
                case .left:
                    distanceFromBase = self.bounds.width - convertedBounds.minX
                }
                scrollView.contentInset.bottom = max(inset - distanceFromBase, 0)
            } else {
                adjustChildContentInset(childView, inset: inset)
            }
        }
    }

    private func createOverlay() -> Overlay? {
        guard let superview = self.superview else {
            log("ERROR: Could not create overlay.")
            return nil
        }

        let overlay = Overlay(frame: superview.bounds)
        overlay.isHidden = self.isHidden
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.alpha = 0
        overlayTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onTapOverlay))
        overlay.addGestureRecognizer(overlayTapRecognizer)

        superview.insertSubview(overlay, belowSubview: self)
        let constraints: [NSLayoutConstraint]
        switch orientation {
        case .bottom:
            constraints = [
                overlay.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                overlay.heightAnchor.constraint(equalTo: superview.heightAnchor),
                overlay.bottomAnchor.constraint(equalTo: self.topAnchor)
            ]
        case .top:
            constraints = [
                overlay.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                overlay.heightAnchor.constraint(equalTo: superview.heightAnchor),
                overlay.topAnchor.constraint(equalTo: self.bottomAnchor)
            ]
        case .left:
            constraints = [
                overlay.topAnchor.constraint(equalTo: superview.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                overlay.widthAnchor.constraint(equalTo: superview.widthAnchor),
                overlay.leadingAnchor.constraint(equalTo: self.trailingAnchor)
            ]
        case .right:
            constraints = [
                overlay.topAnchor.constraint(equalTo: superview.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                overlay.widthAnchor.constraint(equalTo: superview.widthAnchor),
                overlay.trailingAnchor.constraint(equalTo: self.leadingAnchor)
            ]
        }

        for constraint in constraints {
            constraint.isActive = true
        }

        updateOverlayVisuals(overlay)

        return overlay
    }

    private func setOverlayOpacity(forScrollPosition position: CGFloat) {
        guard let superview = self.superview else {
            log("ERROR: Could not set up overlay.")
            return
        }

        guard shouldShowOverlay else {
            self.overlay?.alpha = 0
            return
        }

        let values = snapPositions(for: DrawerPosition.allPositions, inSuperView: superview)
            .map {(
                position: $0.snapPosition,
                value: self.opacityFactor(for: $0.position)
                )}

        let opacityFactor = interpolate(
            values: values,
            position: position)

        let maxOpacity: CGFloat = 0.5

        if opacityFactor > 0 {
            self.overlay = self.overlay ?? createOverlay()
            self.overlay?.alpha = opacityFactor * maxOpacity
        } else {
            self.overlay?.removeFromSuperview()
            self.overlay = nil
        }
    }

    private func setShadowOpacity(forScrollPosition position: CGFloat) {
        guard let superview = self.superview else {
            log("ERROR: Could not set up shadow.")
            return
        }

        let values = snapPositions(for: DrawerPosition.allPositions, inSuperView: superview)
            .map {(
                position: $0.snapPosition,
                value: CGFloat(self.shadowOpacityFactor(for: $0.position))
                )}

        let shadowOpacity = interpolate(
            values: values,
            position: position)

        self.layer.shadowOpacity = Float(shadowOpacity)
    }

    private func setChildrenOpacity(forScrollPosition position: CGFloat) {
        guard let superview = self.superview else {
            return
        }

        // TODO: This method doesn't take into account if a child view opacity was changed while it is hidden.

        if self.inset > 0 {

            // Measure the distance to collapsed position.
            let snap = self.snapPosition(for: .collapsed, inSuperView: superview)
            let alpha = min(1, (snap - position) / self.inset)

            if alpha < 1 {
                // Ask only once when beginning to hide child views.
                let viewsToHide = self.hiddenChildViews ?? self.childViewsToHide()
                self.hiddenChildViews = viewsToHide

                viewsToHide.forEach { view in
                    view.alpha = alpha
                }

            } else {
                if let hiddenViews = self.hiddenChildViews {
                    hiddenViews.forEach { view in
                        view.alpha = 1
                    }
                }
                self.hiddenChildViews = nil
            }

            currentChildOpacity = alpha
        }
    }

    // MARK: - Helpers

    private func childViewsToHide() -> [UIView] {
        guard let superview = self.superview else {
            return []
        }

        var allowPartial = false
        switch self.contentVisibilityBehavior {
        case .allowPartial:
            allowPartial = true
            fallthrough
        case .automatic:
            // Hide all the views that are not completely above the horizon.
            let snap = self.snapPosition(for: .collapsed, inSuperView: superview)
            return (embeddedView ?? self).subviews.filter {
                $0 !== self.backgroundView && $0 !== self.borderView
                    && (allowPartial ? $0.frame.minY > snap : $0.frame.maxY > snap)
            }
        case .custom(let handler):
            return handler()
        case .never:
            return []

        }
    }

    private var currentSnapPosition: CGFloat {
        return self.marginConstraint?.constant ?? 0
    }

    private func convertScrollPositionToOffset(_ position: CGFloat) -> CGFloat {
        guard let superview = self.superview else {
            return 0
        }
        let base = isOrientedVertically ? superview.bounds.height : superview.bounds.width
        let corrector: CGFloat = isDirectOrientation ? 1 : -1
        return base - corrector * position
    }

    private func ableToDetermineOppositeDirectionPan(_ scrollView: UIScrollView) -> Bool {
        let hasDirectionalLock = (scrollView is UITableView) || scrollView.isDirectionalLockEnabled
        // If vertical scroll is not possible, or directional lock is
        // enabled, we are able to detect if view was panned horizontally.
        var scrollFlag = false
        switch orientation {
        case .bottom, .top:
            scrollFlag = !scrollView.canScrollVertically
        default:
            scrollFlag = scrollView.canScrollVertically
        }
        return scrollFlag || hasDirectionalLock
    }

    private func shouldWarn(_ lastWarningDate: inout Date?) -> Bool {
        let warn: Bool
        if let date = lastWarningDate {
            warn = date.timeIntervalSinceNow > 30
        } else {
            warn = true
        }
        lastWarningDate = Date()
        return warn
    }
}

// MARK: - Extensions

extension DrawerView: UIGestureRecognizerDelegate {

    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer || gestureRecognizer === overlayTapRecognizer {
            return enabled
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if gestureRecognizer === self.panGestureRecognizer {
            if let scrollView = otherGestureRecognizer.view as? UIScrollView {

                if let index = self.childScrollViews.firstIndex(where: { $0.scrollView === scrollView }) {
                    // Existing scroll view, update it.
                    let scrollInfo = self.childScrollViews[index]
                    self.childScrollViews[index].gestureRecognizers = scrollInfo.gestureRecognizers + [otherGestureRecognizer]
                } else {
                    // New entry.
                    self.childScrollViews.append(ChildScrollViewInfo(
                        scrollView: scrollView,
                        scrollWasEnabled: scrollView.isScrollEnabled,
                        gestureRecognizers: []))
                }
                return true
            } else if otherGestureRecognizer.view is UITextField {
                return true
            }
        }

        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {

        if gestureRecognizer !== self.panGestureRecognizer {
            if otherGestureRecognizer.view is UIScrollView {
                // If the gesture recognizer is from a scroll view, do not fail as
                // we need to work in parallel
                return false
            }

            if otherGestureRecognizer.view is UITextField {
                return false
            }
        }

        return false
    }

}

// MARK: - Private Extensions

fileprivate extension DrawerView {

    var snapPositionsDescending: [DrawerPosition] {
        return self.snapPositions
            .sortedBySnap(in: self, ascending: false)
            .map { $0.position }
    }

    func getPosition(offsetBy offset: Int) -> DrawerPosition? {
        return snapPositionsDescending.advance(from: self.position, offset: offset)
    }
}


fileprivate extension CGRect {

    func insetBy(top: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0, right: CGFloat = 0) -> CGRect {
        return CGRect(
            x: self.origin.x + left,
            y: self.origin.y + top,
            width: self.size.width - left - right,
            height: self.size.height - top - bottom)
    }
}

public extension BidirectionalCollection where Element == DrawerPosition {

    /// A simple utility function that goes through a collection of `DrawerPosition` items. Note
    /// that positions are treated in the same order they are provided in the collection.
    func advance(from position: DrawerPosition, offset: Int) -> DrawerPosition? {
        guard !self.isEmpty else {
            return nil
        }

        if let index = self.firstIndex(of: position) {
            let nextIndex = self.index(index, offsetBy: offset)
            return self.indices.contains(nextIndex) ? self[nextIndex] : nil
        } else {
            return nil
        }
    }

}

fileprivate extension Collection where Element == DrawerPosition {

    func sortedBySnap(in drawerView: DrawerView, ascending: Bool) -> [(position: DrawerPosition, snap: CGFloat)] {
        guard let superview = drawerView.superview else {
            return []
        }

        return self
            .map { ($0, drawerView.snapPosition(for: $0, inSuperView: superview))}
            .sorted(by: {
                ascending
                    ? $0.snap < $1.snap
                    : $0.snap > $1.snap
            })
    }
}

fileprivate extension UIGestureRecognizer {

    func isActive() -> Bool {
        return self.isEnabled && (self.state == .changed || self.state == .began)
    }
}

fileprivate extension UIScrollView {

    var canScrollVertically: Bool {
        return self.contentSize.height > self.bounds.height
    }

    var canScrollHorizontally: Bool {
        return self.contentSize.width > self.bounds.width
    }
}

fileprivate extension UIGestureRecognizer.State {

    var isTracking: Bool {
        return self == .began || self == .changed
    }
}

#if !swift(>=4.2)
fileprivate extension Array {

    // Backwards support for compactMap.
    public func compactMap<ElementOfResult>(_ transform: (Element) throws -> ElementOfResult?) rethrows -> [ElementOfResult] {
        return try self.flatMap(transform)
    }
}
#endif

// MARK: - Private functions

fileprivate func damp(value: CGFloat, factor: CGFloat) -> CGFloat {
    return factor * (log10(value + factor/log(10)) - log10(factor/log(10)))
}

fileprivate func abort(reason: String) -> Never  {
    NSLog("DrawerView: \(reason)")
    abort()
}

fileprivate func log(_ message: String) {
    if LOGGING {
        print("\(dateFormatter.string(from: Date())): \(message)")
    }
}

