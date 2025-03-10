#!/usr/bin/swift

import Foundation 

func copyDir(src: String, dest: String) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: dest, withIntermediateDirectories: true)

    let items = try fileManager.contentsOfDirectory(atPath: src)
    for item in items {
        let srcPath = "\(src)/\(item)"
        let destPath = "\(dest)/\(item)"

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: srcPath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                try copyDir(src: srcPath, dest: destPath)
            } else {
                try fileManager.copyItem(atPath: srcPath, toPath: destPath)
            }
        }
    }
}

func copyDependencies() {
    do {
        let fileManager = FileManager.default
        
        // Use absolute paths that we know work from the debug output
        let coreSrc = "/Users/gauntlet/Desktop/tinyvec/src/core"
        let targetDir = "/Users/gauntlet/Desktop/tinyvec/bindings/swift"
        
        print("Source path: \(coreSrc)")
        print("Target path: \(targetDir)")
        
        // Create the Swift package structure directories
        let sourcesDir = "\(targetDir)/Sources/Ccore"
        
        // Only try to copy if the source exists
        if fileManager.fileExists(atPath: "\(coreSrc)/include") {
            try copyDir(src: "\(coreSrc)/include", dest: "\(sourcesDir)/include")
            try copyDir(src: "\(coreSrc)/src", dest: "\(sourcesDir)/src")
            print("Successfully copied core files to Swift Package Manager structure:")
            print("  - \(sourcesDir)/include")
            print("  - \(sourcesDir)/src")
            
            // Create a basic module.modulemap file if it doesn't exist
            let modulemapPath = "\(sourcesDir)/module.modulemap"
            if !fileManager.fileExists(atPath: modulemapPath) {
                let modulemapContent = """
                module Ccore {
                    umbrella header "include/vec_types.h"
                    header "include/db.h"
                    header "include/file.h"
                    export *
                }
                """
                try modulemapContent.write(toFile: modulemapPath, atomically: true, encoding: .utf8)
                print("  - Created module.modulemap for C bindings")
            }
        } else {
            print("Source directory \(coreSrc)/include doesn't exist!")
            print("Please verify the correct path to the core code.")
        }
    } catch {
        fputs("Error copying dependencies: \(error)", stderr)
        exit(1)
    }
}

copyDependencies()