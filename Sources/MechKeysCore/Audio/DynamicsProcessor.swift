import AudioToolbox
import AVFoundation
import Foundation

/// Apple's `AUDynamicsProcessor`, wrapped as an `AVAudioUnitEffect`.
///
/// AVFoundation ships convenience subclasses for EQ, reverb, delay and
/// distortion, but not for dynamics — the compressor has to be instantiated
/// from its Audio Unit component description. The parameters are reached
/// through `auAudioUnit.parameterTree`; the older `AudioUnitSetParameter`
/// route on `.audioUnit` is deprecated as of macOS 27.
///
/// `AUParameter` objects are looked up once at init and reused, so setting a
/// value at runtime is a single atomic store rather than a tree search.
public final class DynamicsProcessor: AVAudioUnitEffect, @unchecked Sendable {

    /// Parameter addresses, from `AudioUnitParameters.h`.
    private enum Address: AUParameterAddress {
        case threshold = 0
        case headRoom = 1
        case expansionRatio = 2
        case expansionThreshold = 3
        case attackTime = 4
        case releaseTime = 5
        case overallGain = 6
    }

    private var parameters: [AUParameterAddress: AUParameter] = [:]

    override public init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        super.init(audioComponentDescription: description)

        if let tree = auAudioUnit.parameterTree {
            for parameter in tree.allParameters {
                parameters[parameter.address] = parameter
            }
        }
    }

    private func set(_ address: Address, _ value: Float) {
        guard let parameter = parameters[address.rawValue] else { return }
        parameter.setValue(value.clamped(to: parameter.minValue...parameter.maxValue), originator: nil)
    }

    /// Level above which compression begins, in dBFS.
    public var threshold: Float = -35 {
        didSet { set(.threshold, threshold) }
    }

    /// Softness of the knee, in dB. Less headroom is a harder squeeze.
    public var headRoom: Float = 30 {
        didSet { set(.headRoom, headRoom) }
    }

    public var attackTime: Float = 0.03 {
        didSet { set(.attackTime, attackTime) }
    }

    public var releaseTime: Float = 0.03 {
        didSet { set(.releaseTime, releaseTime) }
    }

    /// Output makeup gain, in dB.
    public var overallGain: Float = 0 {
        didSet { set(.overallGain, overallGain) }
    }

    /// Applies every parameter in one go.
    public func configure(threshold: Float,
                          headRoom: Float,
                          attackTime: Float,
                          releaseTime: Float,
                          overallGain: Float) {
        self.threshold = threshold
        self.headRoom = headRoom
        self.attackTime = attackTime
        self.releaseTime = releaseTime
        self.overallGain = overallGain
    }
}
