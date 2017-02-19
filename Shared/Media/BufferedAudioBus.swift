//
//  BufferedAudioBus.swift
//  WaveLabs
//
//  Created by Vlad Gorlov on 08/10/2016.
//  Copyright © 2016 WaveLabs. All rights reserved.
//

import AVFoundation

class BufferedAudioBus {
    
    fileprivate var maxFrames: AUAudioFrameCount = 0
    var pcmBuffer: AVAudioPCMBuffer?
    fileprivate var originalmData = [UnsafeMutableRawPointer?]()
    private(set) var bus: AUAudioUnitBus
    
    init(format: AVAudioFormat, maxChannels: AVAudioChannelCount) throws {
        bus = try AUAudioUnitBus(format: format)
        bus.maximumChannelCount = maxChannels
    }
    
    func allocateRenderResources(maxFrames: AUAudioFrameCount) {
        self.maxFrames = maxFrames
        pcmBuffer = AVAudioPCMBuffer(pcmFormat: bus.format, frameCapacity: maxFrames)
        pcmBuffer?.frameLength = maxFrames
        guard let mbl = UnsafeMutableAudioBufferListPointer(pcmBuffer?.mutableAudioBufferList) else{ return }
        for i in 0..<mbl.count {
            originalmData.append(mbl[i].mData)
        }
    }
    
    func deallocateRenderResources() {
        pcmBuffer = nil
        originalmData = []
    }
    
}

class BufferedInputBus: BufferedAudioBus {
    
    private func prepareInputBufferList() {
        guard let pcmBuffer = pcmBuffer else { return }
        let mblp = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        for index in 0 ..< mblp.count {
            mblp[index].mData = originalmData[index]
        }
    }
    
    func pull(actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timestamp: UnsafePointer<AudioTimeStamp>,
              frameCount: AUAudioFrameCount, inputBusNumber: Int, pullBlock: AURenderPullInputBlock) -> AUAudioUnitStatus {
        guard let pcmBuffer = pcmBuffer else {
            return kAudioUnitErr_Uninitialized
        }
        prepareInputBufferList()
        return pullBlock(actionFlags, timestamp, frameCount, inputBusNumber, pcmBuffer.mutableAudioBufferList)
    }
}

class BufferedOutputBus: BufferedAudioBus {
    
    func prepareOutputBufferList(_ outputBufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: AUAudioFrameCount,
                                 zeroFill: Bool = false) {
        pcmBuffer?.frameLength = frameCount
        let outputBufferListPointer = UnsafeMutableAudioBufferListPointer(outputBufferList)
        guard originalmData.count == outputBufferListPointer.count else {
            fatalError()//Uninitialized
        }
        for index in 0 ..< outputBufferListPointer.count {
            if outputBufferListPointer[index].mData == nil {
                outputBufferListPointer[index].mData = originalmData[index]
            }
            
            if zeroFill {
                pcmBuffer?.floatChannelData?[index].initialize(to: 0, count: Int(frameCount))
            }
        }
    }
}
