//
//  Extensions.swift
//  DrawerView
//
//  Created by Mikko Välimäki on 2018-02-04.
//  Copyright © 2018 Mikko Välimäki. All rights reserved.
//

import UIKit

public extension UIViewController {

    func addDrawerView(withViewController viewController: UIViewController,
                              parentView: UIView? = nil,
                              orientation: DrawerOrientation = .bottom) -> DrawerView {
        #if swift(>=4.2)
        self.addChild(viewController)
        #else
        self.addChildViewController(viewController)
        #endif
        let drawer = DrawerView(withView: viewController.view, orientation: orientation)
        drawer.attachTo(view: self.view)
        return drawer
    }
}


