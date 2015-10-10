Configuration HighPerformance {
    Node "localhost" {
        Script HighPerformancePowerPlan{  
            SetScript   = { Powercfg -SETACTIVE SCHEME_MIN }  
            TestScript  = { return ( Powercfg -getactivescheme) -like "*High Performance*" }  
            GetScript   = { return @{ Powercfg = ( "{0}" -f ( powercfg -getactivescheme ) ) } }
        }
    }
}
