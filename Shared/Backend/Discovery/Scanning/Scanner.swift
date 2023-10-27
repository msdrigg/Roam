import Network
import Darwin
import Foundation

struct IP4Address: Comparable, Equatable, Strideable {
    func distance(to other: IP4Address) -> Int {
        Int(other.address) - Int(self.address)
    }
    
    func advanced(by n: Int) -> IP4Address {
        let address: UInt32 = UInt32(Int(address) + n)
        return IP4Address(address: address)
    }
    
    typealias Stride = Int
    
    private let address: UInt32
    
    private init(address: UInt32) {
        self.address = address
    }
    init?(string: String) {
        guard let address = ipToUInt32(string) else {
            return nil
        }
        
        self.address = address
    }
    
    var addressString: String {
        uInt32ToIP(address)
    }
    
    func localNetworkRange(subnetMask: IP4Address) -> Range<IP4Address> {
        let networkAddressInt = self.address & subnetMask.address
        let broadcastAddressInt = networkAddressInt | ~subnetMask.address
        
        return IP4Address(address: networkAddressInt)..<IP4Address(address: broadcastAddressInt)
    }
}

struct Addressed4NetworkInterface {
    let name: String
    let family: Int32
    let address: IP4Address
    let netmask: IP4Address
    let flags: UInt32
    let nwInterface: NWInterface?
    
    var isEthernetLike: Bool {
        self.nwInterface?.type == .wifi || self.nwInterface?.type == .wifi
    }
    
    var isIPV4: Bool {
        family == AF_INET
    }
    
    var scannableIPV4NetworkRange: Range<IP4Address> {
        address.localNetworkRange(subnetMask: netmask)
    }
    
    func withNWInterface(_ iface: NWInterface?) -> Addressed4NetworkInterface {
        return Addressed4NetworkInterface(name: name, family: family, address: address, netmask: netmask, flags: flags, nwInterface: iface)
    }
}

func allAddressedInterfaces() async -> [Addressed4NetworkInterface] {
    let darwinInterfaces = listInterfacesDarwin()
    let nwInterfaces = await listInterfacesNW()
    var combinedInterfaces: [Addressed4NetworkInterface] = []
    
    for netInterface in darwinInterfaces {
        if let matched = nwInterfaces.first(where: { $0.name == netInterface.name }) {
            combinedInterfaces.append(netInterface.withNWInterface(matched))
        }
    }
    
    return combinedInterfaces
}

private func ipToUInt32(_ ip: String) -> UInt32? {
    let segments = ip.split(separator: ".")
    guard segments.count == 4 else { return nil }
    
    var result: UInt32 = 0
    for segment in segments {
        guard let octet = UInt32(segment), octet < 256 else { return nil }
        result = (result << 8) + octet
    }
    
    return result
}

private func uInt32ToIP(_ intVal: UInt32) -> String {
    var remaining = intVal
    var segments: [UInt32] = []
    
    for _ in 0..<4 {
        let segment = remaining & 0xFF
        segments.insert(segment, at: 0)
        remaining >>= 8
    }
    
    return segments.map(String.init).joined(separator: ".")
}

private func listInterfacesDarwin() -> [Addressed4NetworkInterface] {
    var addrList: UnsafeMutablePointer<ifaddrs>?
    var networkInterfaces: [Addressed4NetworkInterface] = []
    
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
                let addressString = String(cString: host)
                let netmaskString = String(cString: netmask)
                if let address = IP4Address(string: addressString), let netmask = IP4Address(string: netmaskString) {
                    networkInterfaces.append(Addressed4NetworkInterface(name: name, family: Int32(family), address: address, netmask: netmask, flags: flags, nwInterface: nil))
                }
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
        monitor.pathUpdateHandler = { path in     
            continuation.resume(returning: path.availableInterfaces)
        }
    }
    
    monitor.cancel()
    return matchedNWInterfaces
}
