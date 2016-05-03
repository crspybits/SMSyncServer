//
//  SyncSpinner.swift
//  SharedNotes
//
//  Created by Christopher Prince on 4/27/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit

class SyncSpinner : UIView {
    private var icon = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let image = UIImage(named: "SyncSpinner")
        self.icon.image = image
        self.icon.contentMode = .ScaleAspectFit
        self.icon.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
        var iconFrame = frame;
        iconFrame.origin = CGPointZero
        self.icon.frame = iconFrame
        self.addSubview(self.icon)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let animationKey = "rotationAnimation"
    
    func start() {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.toValue = M_PI * 2.0
        rotationAnimation.duration = 1
        rotationAnimation.cumulative = true
        rotationAnimation.repeatCount = Float.infinity
        self.icon.layer.addAnimation(rotationAnimation, forKey: self.animationKey)
    }
    
    func stop() {
        self.icon.layer.removeAllAnimations()
    }
}