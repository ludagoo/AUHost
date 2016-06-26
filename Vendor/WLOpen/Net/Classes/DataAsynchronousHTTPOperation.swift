//
//  DataAsynchronousHTTPOperation.swift
//  WLNet
//
//  Created by Volodymyr Gorlov on 17.12.15.
//  Copyright © 2015 WaveLabs. All rights reserved.
//

import Foundation

public class DataAsynchronousHTTPOperation: AsynchronousOperation {

	private var _result = Property<ResultType<NSData>>(.Failure(NetworkOperationError.InvalidOperationState))
	private var url: NSURL
	private var session: NSURLSession
	private var task: NSURLSessionDataTask?

	public var result: ResultType<NSData> {
		return _result.value
	}

	public init(session aSession: NSURLSession, URL anURL: NSURL) {
		url = anURL
		session = aSession
		super.init()
	}

	public override func onStart() {
		task = session.dataTaskWithURL(url) {[weak self] data, response, error in
			guard let s = self where !s.cancelled else { return }
			defer {
				s.finish()
			}
			if let e = error {
				s._result.value = .Failure(e)
				return
			}
			guard let resp = response as? NSHTTPURLResponse else {
				s._result.value = .Failure(NetworkError.UnexpectedResponse("Response is not NSHTTPURLResponse"))
				return
			}
			if resp.statusCode == 200 {
				guard let d = data else {
					s._result.value = .Failure(SerializationError.UnableToDecode("Unable to get data from response"))
					return
				}
				s._result.value = .Success(d)
			} else {
				s._result.value = .Failure(NetworkError.UnexpectedResponse("Server respond with HTTP code \(resp.statusCode)"))
			}
		}
		task?.resume()
	}

	public override func onCancel() {
		task?.cancel()
		task = nil
	}

	public override func onFinish() {
		task = nil
	}

}