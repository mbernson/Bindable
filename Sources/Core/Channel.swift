//
//  Channel.swift
//  Bindable
//
//  Created by Tom Lokhorst on 2017-03-16.
//
//

import Foundation

public class Channel<Event> {
  internal let source: ChannelSource<Event>

  internal init(source: ChannelSource<Event>) {
    self.source = source
  }

  public func subscribe(_ handler: @escaping (Event) -> Void) -> Subscription {

    let h = ChannelHandler(channel: self, handler: handler)
    source.internalState.addHandler(h)

    return h
  }

  public func map<NewEvent>(_ transform: @escaping (Event) -> NewEvent) -> Channel<NewEvent> {
    let resultSource = ChannelSource<NewEvent>(queue: source.queue)

    _ = source.channel.subscribe { event in
      resultSource.post(transform(event))
    }

    return resultSource.channel
  }

  public func dispatch(on dispatchQueue: DispatchQueue) -> Channel<Event> {
    let resultSource = ChannelSource<Event>(queue: dispatchQueue)

    _ = self.subscribe { event in
      resultSource.post(event)
    }

    return resultSource.channel
  }
}

public class ChannelSource<Event> {
  private let dispatchKey = DispatchSpecificKey<Void>()

  fileprivate let internalState: ChannelSourceState

  internal let queue: DispatchQueue

  public init(queue: DispatchQueue = DispatchQueue.main) {
    self.internalState = ChannelSourceState()
    self.queue = queue

    queue.setSpecific(key: dispatchKey, value: ())
  }

  deinit {
    queue.setSpecific(key: dispatchKey, value: nil)
  }

  public var channel: Channel<Event> {
    return Channel(source: self)
  }

  public func post(_ event: Event) {
    let handlers = internalState.getHandlers()
    let async = DispatchQueue.getSpecific(key: dispatchKey) == nil

    for h in handlers {
      guard let handler = h.handler else { continue }

      if async {
        queue.async {
          handler(event)
        }
      }
      else {
        handler(event)
      }
    }
  }
}

extension ChannelSource {
  fileprivate class ChannelSourceState {
    private let lock = NSLock()
    private var handlers: [ChannelHandler<Event>] = []

    func addHandler(_ handler: ChannelHandler<Event>) {
      lock.lock(); defer { lock.unlock() }

      handlers.append(handler)
    }

    func getHandlers() -> [ChannelHandler<Event>] {
      lock.lock(); defer { lock.unlock() }

      return handlers
    }

    func removeSubscription(_ subscription: Subscription) {
      lock.lock(); defer { lock.unlock() }

      for (ix, handler) in handlers.enumerated() {
        if handler === subscription {
          handlers.remove(at: ix)
        }
      }
    }

  }
}

class ChannelHandler<Value>: Subscription {
  weak var channel: Channel<Value>?
  private(set) var handler: ((Value) -> Void)?

  init(channel: Channel<Value>, handler: @escaping (Value) -> Void) {
    self.channel = channel
    self.handler = handler
  }

  func unsubscribe() {
    channel?.source.internalState.removeSubscription(self)
    handler = nil
  }
}
