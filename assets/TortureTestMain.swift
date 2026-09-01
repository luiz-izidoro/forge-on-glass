// main.swift do TortureTest.
// REGRA DO SWIFT: codigo top-level so e' permitido num arquivo chamado main.swift
// (ou passado como tal). Ao compilar VARIOS .swift juntos, o entry point precisa
// ficar isolado aqui.
import Foundation
import UIKit
import CoreText
import Dispatch

UIApplicationMain(CommandLine.argc,
                  CommandLine.unsafeArgv,
                  nil,
                  NSStringFromClass(AppDelegate.self))
