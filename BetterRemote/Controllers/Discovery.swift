import Network
import Darwin
import Foundation

typealias IPAddress = String

struct NetworkInterface {
    let name: String
    let family: Int32
    let address: String
    let netmask: String
    let flags: UInt32
    let nwInterface: NWInterface?
    
    var isEthernetLike: Bool {
        self.nwInterface?.type == .wifi || self.nwInterface?.type == .wifi
    }
    
    var isIPV4: Bool {
        family == AF_INET
    }
    
    var scannableIPV4NetworkRange: Range<UInt32>? {
        getLocalNetworkRange(localIP: address, subnetMask: netmask)
    }
    
    func withNWInterface(_ iface: NWInterface?) -> NetworkInterface {
        return NetworkInterface(name: name, family: family, address: address, netmask: netmask, flags: flags, nwInterface: iface)
    }
}

func getAllInterfaces() async -> [NetworkInterface] {
    let darwinInterfaces = listInterfacesDarwin()
    let nwInterfaces = await listInterfacesNW()
    var combinedInterfaces: [NetworkInterface] = []
    
    for netInterface in darwinInterfaces {
        if let matched = nwInterfaces.first(where: { $0.name == netInterface.name }) {
            combinedInterfaces.append(netInterface.withNWInterface(matched))
        }
    }
    
    return combinedInterfaces
}

func ipToUInt32(_ ip: IPAddress) -> UInt32? {
    let segments = ip.split(separator: ".")
    guard segments.count == 4 else { return nil }
    
    var result: UInt32 = 0
    for segment in segments {
        guard let octet = UInt32(segment), octet < 256 else { return nil }
        result = (result << 8) + octet
    }
    
    return result
}

func uInt32ToIP(_ intVal: UInt32) -> IPAddress {
    var remaining = intVal
    var segments: [UInt32] = []
    
    for _ in 0..<4 {
        let segment = remaining & 0xFF
        segments.insert(segment, at: 0)
        remaining >>= 8
    }
    
    return segments.map(String.init).joined(separator: ".")
}

private func listInterfacesDarwin() -> [NetworkInterface] {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    var networkInterfaces: [NetworkInterface] = []
    
    if getifaddrs(&addrList) == 0 {
        var ptr = addrList
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let addr = ptr?.pointee else { continue }
            
            let name = String(cString: addr.ifa_name)
            let flags = addr.ifa_flags
            let family = addr.ifa_addr?.pointee.sa_family ?? 0
            
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let ifa_addr = addr.ifa_addr {
                getnameinfo(ifa_addr, socklen_t(ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
            }
            
            var netmask = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if let ifa_netmask = addr.ifa_netmask {
                getnameinfo(ifa_netmask, socklen_t(ifa_netmask.pointee.sa_len),
                            &netmask, socklen_t(netmask.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
            }
            if family == AF_INET || family == AF_INET6 {
                networkInterfaces.append(NetworkInterface(name: name, family: Int32(family), address: String(cString: host), netmask: String(cString: netmask), flags: flags, nwInterface: nil))
            }
        }
        freeifaddrs(addrList)
    }
    return networkInterfaces
}


private func listInterfacesNW() async -> [NWInterface] {
    let monitor = NWPathMonitor()
    monitor.start(queue: DispatchQueue.global())
    
    let matchedNWInterfaces = await withCheckedContinuation { continuation in
        monitor.pathUpdateHandler = { path in            continuation.resume(returning: path.availableInterfaces)
        }
    }
    
    monitor.cancel()
    return matchedNWInterfaces
}


private func getLocalNetworkRange(localIP: IPAddress, subnetMask: IPAddress) -> Range<UInt32>? {
    guard let localIPInt = ipToUInt32(localIP),
          let subnetMaskInt = ipToUInt32(subnetMask) else { return nil }
    
    let networkAddressInt = localIPInt & subnetMaskInt
    let broadcastAddressInt = networkAddressInt | ~subnetMaskInt
    
    return networkAddressInt..<broadcastAddressInt
}
