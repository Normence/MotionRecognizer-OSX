//
//  main.swift
//  MotionRecognizer
//
//  Created by Wenyu Luo on 16/9/3.
//  Copyright © 2016年 Wenyu Luo. All rights reserved.
//

import Foundation

//parameters
let defaultMapID = 96
let defaultPoseID = 3
let defaultTraceID = 4

let dataUpdateInterval = 1.0 / 50.0
let refreshTime = Int(1.0 / dataUpdateInterval)

let dataItemNumber = 16
let defaultMinτ = 40
let defaultMaxτ = 100

let accX = 6   // my：1/2/3，bo-iOS：6/7/8
let accY = 7
let accZ = 8
let separator = ","   //my：" ", bo：","
/////

enum motionStatus: Int {
    case MOVING = -1
    case IDLE, WALKING
}

var mapID = defaultMapID
var poseID = defaultPoseID
var traceID = defaultTraceID
var fileManager = NSFileManager.defaultManager()
var dataFileHandle = NSFileHandle.init()
var outputFileHandle = NSFileHandle.init()
var datas: [String]? = []
var dataLen = 0
var dataCount = 1
var dataEnd = 0
var τMax = defaultMaxτ
var τMin = defaultMinτ
var status = motionStatus.IDLE
var test = true


func calculateSD(datas: [String]?, begin: Int, end: Int) -> Double {
    var stop: Int
    
    if end > (dataLen - 1) {
        stop = (dataLen - 1)
    } else {
        stop = end
    }
    
    let nums = (end - begin + 1)
    
    var avg = 0.00
    
    //get mean
    avg = calculateAvg(datas, begin: begin, end: end)
    
    //get Standard Deviation
    var sum = 0.00
    for i in begin...end {
        if i < dataLen{
            if !datas![i].isEmpty{
                let norm = Double(datas![i])!
                sum += square(norm - avg)
            }
        } else {
            sum += square(0 - avg)
        }
    }
    
    avg = sum / Double(nums)
    
    return sqrt(avg)
}

func square(x: Double) -> Double {
    return x * x
}

func calculateAvg(datas: [String]?, begin: Int, end: Int) -> Double {
    var stop: Int
    
    if end > (dataLen - 1) {
        stop = dataLen - 1
    } else {
        stop = end
    }
    
    let nums = (end - begin + 1)
    
    var sum = 0.00
    
    //get sum
    for i in begin...stop {
        if i < dataLen{
            if !datas![i].isEmpty {
                sum += Double(datas![i])!
            }
        }
    }
    
    let avg = sum / Double(nums)
    return avg
}

func calculateNAC(datas: [String]?, begin: Int, end: Int) -> Double {  //{∑<k=0...k=τ-1> [(a(m+k)-μ(m,τ))·(a(m+k+τ)-μ(m+τ,τ))]}/τσ(m,τ)σ(m+τ,τ)
    
    let τ = (end - begin + 1)
    let μ_m_τ = calculateAvg(datas, begin: begin, end: end)
    let σ_m_τ = calculateSD(datas, begin: begin, end: end)
    var μ_m＋τ_τ: Double
    var σ_m＋τ_τ: Double
    
    if (begin + τ) >= dataLen {
        μ_m＋τ_τ = 0.00
        σ_m＋τ_τ = 0.00
    } else {
        μ_m＋τ_τ = calculateAvg(datas, begin: begin + τ, end: end + τ)
        σ_m＋τ_τ = calculateSD(datas, begin: begin + τ, end: end + τ)
    }
    
    
    var sum = 0.00
    
    for i in begin...end {
        var temp1 = 0.00
        var temp2 = 0.00
        
        if i < dataLen{
            if !datas![i].isEmpty {
                let norm = Double(datas![i])!
                temp1 += (norm - μ_m_τ)
            }
        } else {
            temp1 -= μ_m_τ
        }
        
        if (i + τ) < dataLen{
            if !datas![i+τ].isEmpty {
                    let norm = Double(datas![i+τ])!
                    temp2 += (norm - μ_m＋τ_τ)
            }
        } else {
            temp2 -= μ_m＋τ_τ
        }
        
        sum += (temp1 * temp2)
    }
    
    let temp3 = (Double(τ) * σ_m_τ * σ_m＋τ_τ)
    
    var nac: Double
    if temp3 != 0 {
        nac = sum / temp3
    } else {
        nac = 0
    }
    
    return nac
}

func max(x: Double, y: Double, z: Double) -> Double {
    if x > y {
        if x > z {
            return x
        } else {
            return z
        }
    } else {
        if y > z {
            return y
        } else {
            return z
        }
    }
}

func motionRecognition() {
    if dataCount < dataEnd {
        print("dataCount: \(dataCount), dataLen: \(dataLen)， dataEnd: \(dataEnd)")
        
        let sd = calculateSD(datas, begin: dataCount, end: dataCount + Int(1.0 / dataUpdateInterval) - 1)  //50Hz sampling frequency with 50 samples per second
        
        var outputString = ""
        if sd < 0.01 {
            //idle
            status = .IDLE
            print("Motion Recognized as IDLE with index: \(dataCount), sd: \(sd)")
            outputString = "0, \(dataCount), \(sd)\n"
            τMax = defaultMaxτ
            τMin = defaultMinτ
        } else {
            //walking or moving
            //get the maximum Normalized Auto-Correlation and the corresponding τ
            var nacMax = 0.00
            var nacMax_τ = 0
            for τ in τMin...τMax {
                let nac = calculateNAC(datas, begin: dataCount, end: dataCount + τ - 1)
                if nac > nacMax {
                    nacMax = nac
                    nacMax_τ = τ
                }
            }
            τMax = nacMax_τ + 10
            τMin = nacMax_τ - 10
            if τMin <= 0 {
                τMax = defaultMaxτ
                τMin = defaultMinτ
            }
            print("τmin: \(τMin), τmax: \(τMax)")
            
            if nacMax > 0.7 {
                //WALKING
                status = .WALKING
                print("Motion Recognized as WALKING with index: \(dataCount), sd: \(sd), MAXNac: \(nacMax), τ: \(nacMax_τ)")
                outputString = "1, \(dataCount), \(sd), \(nacMax), \(nacMax_τ)\n"
            } else {
                //MOVING
                status = .MOVING
                print("Motion Recognized as MOVING with index: \(dataCount), sd: \(sd), MAXNac: \(nacMax), τ: \(nacMax_τ)")
                outputString = "-1, \(dataCount), \(sd), \(nacMax), \(nacMax_τ)\n"
                τMax = defaultMaxτ
                τMin = defaultMinτ
            }
            
        }
        outputFileHandle.writeData(outputString.dataUsingEncoding(NSUTF8StringEncoding)!)
        
        dataCount += 1
    } else{
        //finish
        print("Finish")
    }
}

let fileName = "parking\(mapID)pose\(poseID)trace\(traceID)"
let directoryPath = "/Users/Normence/Downloads/"
//let dataPath = NSBundle.pathForResource(fileName, ofType: "txt", inDirectory: directoryPath)
//let outputPath = NSBundle.pathForResource(fileName + "(Output)", ofType: "txt", inDirectory: directoryPath)
var dataPath: String? = directoryPath + fileName + ".txt"
var outputPath: String? = directoryPath + fileName + "(Output).txt"

if fileManager.fileExistsAtPath(outputPath!) {
    do{
        try fileManager.removeItemAtPath(outputPath!)
        print("Remove file: " + outputPath!)
    } catch _ as NSError {
        print("Unable to remove file: " + outputPath!)
    }
}

if fileManager.createFileAtPath(outputPath!, contents: nil, attributes: nil) {
    print("Create file: " + outputPath!)
} else {
    print("Unable to create file: " + outputPath!)
    test = false
}

if let d = NSFileHandle.init(forReadingAtPath: dataPath!) {
    dataFileHandle = d
    print("Reading file: " + dataPath!)
} else {
    print("Fail to open file: " + dataPath!)
    test = false
}

if let d = NSFileHandle.init(forWritingAtPath: outputPath!){
    outputFileHandle = d
    print("Writing file: " + outputPath!)
    let s = "Status index s MaxNac τ\n"
    outputFileHandle.writeData(s.dataUsingEncoding(NSUTF8StringEncoding)!)
} else {
    print("Fail to open file: " + outputPath!)
    test = false
}


let data = dataFileHandle.readDataToEndOfFile()
let temp_data = String.init(data: data, encoding: NSUTF8StringEncoding)
let temp_datas = temp_data?.componentsSeparatedByString("\n")

for i in 0..<(temp_datas?.count)! {
    let temp_datas_i = temp_datas![i].componentsSeparatedByString(separator)
    if temp_datas_i.count == 1 {
        continue
    }
    if (Double(temp_datas_i[accX]) != nil) {
        let norm = sqrt(square(Double(temp_datas_i[accX])!) + square(Double(temp_datas_i[accY])!) + square(Double(temp_datas_i[accZ])!))
        datas?.insert(String(norm), atIndex: i)
    } else {
        datas?.insert("0.000", atIndex: i)
    }
}

dataLen = (datas?.count)!
dataCount = 1
dataEnd = dataLen - defaultMaxτ

if test {
    for _ in 1...dataEnd{
        motionRecognition()
    }
}


