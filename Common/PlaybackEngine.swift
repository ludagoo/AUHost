//
//  PlaybackEngine.swift
//  AUHost
//
//  Created by Vlad Gorlov on 17.01.16.
//  Copyright © 2016 WaveLabs. All rights reserved.
//

import AVFoundation
import CoreAudioKit

enum PlaybackEngineStateError: Error {
   case FileIsNotSet
}

enum PlaybackEngineEffectSelectionResult {
   case EffectCleared
   case Success(AVAudioUnit)
   case Failure(Error)
}

enum PlaybackEngineState: Int {
   case Stopped, Playing, Paused, SettingFile, SettingEffect
   var stringValue: String {
      switch self {
      case .Stopped: return "Stopped"
      case .Playing: return "Playing"
      case .Paused: return "Paused"
      case .SettingFile: return "SettingFile"
      case .SettingEffect: return "SettingEffect"
      }
   }
}

enum PlaybackEngineEvent {
   case Play, Pause, Resume, Stop
   case SetFile(AVAudioFile?)
   case SetEffect(AudioComponentDescription?, ((PlaybackEngineEffectSelectionResult) -> Void))
   var intValue: Int {
      switch self {
      case .Play: return 0
      case .Pause: return 1
      case .Resume: return 2
      case .Stop: return 3
      case .SetEffect: return 4
      case .SetFile: return 5
      }
   }
}

typealias SMGraphType = StateMachineGraph<PlaybackEngineState, PlaybackEngineEvent, PlaybackEngineContext>

private let gStateMachineGraph = SMGraphType(initialState: .Stopped) { (state, event) in
   switch state {
   case .Stopped:
      switch event {
      case .Play: return (.Playing, { try $0.play() })
      case .SetFile(let file): return (.SettingFile, { $0.setFileToPlay(file) })
      case .SetEffect(let component, let callback): return (.SettingEffect, { ctx in
         ctx.selectEffect(componentDescription: component, completionHandler: callback)
      })
      case .Pause, .Resume, .Stop: return nil
      }
   case .Playing:
      switch event {
      case .Pause: return (.Paused, { $0.pause() })
      case .Stop: return (.Stopped, { $0.stop() })
      case .SetFile, .Play, .Resume: return nil
      case .SetEffect(let component, let callback): return (.SettingEffect, {
         $0.stopPlayer()
         $0.selectEffect(componentDescription: component, completionHandler: callback)
      })
      }
   case .Paused:
      switch event {
      case .Resume: return (.Playing, { try $0.resume() })
      case .Stop: return (.Stopped, { $0.stop() })
      case .SetFile, .Play, .Pause: return nil
      case .SetEffect(let component, let callback): return (.SettingEffect, {
         $0.stopPlayer()
         $0.selectEffect(componentDescription: component, completionHandler: callback)
      })
      }
   case .SettingEffect:
      switch event {
      case .SetEffect, .SetFile, .Resume: return nil
      case .Stop: return (.Stopped, nil)
      case .Play: return (.Playing, { try $0.startPlayer() })
      case .Pause: return (.Paused, { try $0.scheduleFile() })
      }
   case .SettingFile:
      switch event {
      case .SetEffect, .SetFile, .Resume, .Play, .Pause: return nil
      case .Stop: return (.Stopped, nil)
      }
   }
}

final class PlaybackEngine {

   enum Change {
      case EngineStateChanged(old: PlaybackEngineState, new: PlaybackEngineState)
   }

   // MARK: Private

   private var sm: StateMachine<SMGraphType>
   private let context = PlaybackEngineContext()
   private let _stateAccessLock: NonRecursiveLocking = SpinLock()

   // MARK: Internal

   var changeHandler: ((Change) -> Void)?
   var stateID: PlaybackEngineState {
      return _stateAccessLock.synchronized {
         return sm.state
      }
   }

   // MARK: Internal

   init() {
      sm = StateMachine(context: context, graph: gStateMachineGraph)
      sm.stateChangeHandler = { [weak self] oldState, event, newState in
         Logger.debug(subsystem: .Media, category: .Handle, message: "State changed: \(oldState) => \(newState)")
         DispatchQueue.main.async { [weak self] in
            self?.changeHandler?(Change.EngineStateChanged(old: oldState, new: newState))
         }
      }
      context.filePlaybackCompleted = { [weak self] in guard let s = self else { return }
         Logger.debug(subsystem: .Media, category: .Handle, message: "Playback stopped or file finished playing. Current state: \(s.stateID)")
         guard s.stateID == .Playing else {
            return
         }
         DispatchQueue.main.async { [weak self] in guard let s = self else { return }
            do {
               try s.sm.handleEvent(event: .Stop)
            } catch {
               Logger.error(subsystem: .Media, category: .Handle, message: error)
            }
         }
      }
      Logger.initialize(subsystem: .Media)
   }

   deinit {
      Logger.deinitialize(subsystem: .Media)
   }

   // MARK: - Internal

   func setFileToPlay(_ fileToPlay: AVAudioFile) throws {
      switch stateID {
      case .SettingEffect, .SettingFile, .Stopped: break
      case .Playing, .Paused:
         try sm.handleEvent(event: .Stop)
      }
      try sm.handleEvent(event: .SetFile(fileToPlay))
      try sm.handleEvent(event: .Stop)
   }

   func stop() {
      do {
         try sm.handleEvent(event: .Stop)
      } catch {
         Logger.error(subsystem: .Media, category: .Lifecycle, message: error)
      }
   }

   func pause() {
      do {
         try sm.handleEvent(event: .Pause)
      } catch {
         Logger.error(subsystem: .Media, category: .Lifecycle, message: error)
      }
   }

   func resume() throws {
      try sm.handleEvent(event: .Resume)
   }

   func play() throws {
      try sm.handleEvent(event: .Play)
   }

   func openEffectView(completionHandler: @escaping (NSViewController?) -> Void) {
      if let au = context.effect?.auAudioUnit {
         au.requestViewController(completionHandler: completionHandler)
      } else {
         completionHandler(nil)
      }
   }

   func selectPreset(preset: AUAudioUnitPreset?) {
      guard let avau = context.effect else {
         return
      }
      guard let p = preset else {
         avau.auAudioUnit.currentPreset = nil
         return
      }
      let presetList = avau.auAudioUnit.factoryPresets ?? []
      let matchedPresets = presetList.filter { $0.number == p.number }
      guard let matchedPreset = matchedPresets.first else {
         avau.auAudioUnit.currentPreset = nil
         return
      }
      avau.auAudioUnit.currentPreset = matchedPreset
   }

   func selectEffect(component: AVAudioUnitComponent?, completionHandler: ((PlaybackEngineEffectSelectionResult) -> Void)?) {
      selectEffect(componentDescription: component?.audioComponentDescription, completionHandler: completionHandler)
   }

   // MARK: Private

   func selectEffect(componentDescription: AudioComponentDescription?,
                             completionHandler: ((PlaybackEngineEffectSelectionResult) -> Void)?) {
      var possibleRelaunchEvent: PlaybackEngineEvent?
      switch stateID {
      case .SettingEffect, .SettingFile: break
      case .Stopped: possibleRelaunchEvent = .Stop
      case .Paused: possibleRelaunchEvent = .Pause
      case .Playing: possibleRelaunchEvent = .Play
      }
      let sema = DispatchSemaphore(value: 0)
      let event = PlaybackEngineEvent.SetEffect(componentDescription, { result in
         completionHandler?(result)
         sema.signal()
      })
      DispatchQueue.UserInitiated.async { [weak self] in guard let s = self else { return }
         do {
            try s.sm.handleEvent(event: event)
         } catch {
            Logger.error(subsystem: .Media, category: .Request, message: error)
         }
         sema.wait() {
            guard let relaunchEvent = possibleRelaunchEvent else {
               return
            }
            do {
               try s.sm.handleEvent(event: relaunchEvent)
            } catch {
               Logger.error(subsystem: .Media, category: .Request, message: error)
            }
         }
      }
   }
}
