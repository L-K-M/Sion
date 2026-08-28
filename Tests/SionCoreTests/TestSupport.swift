import Foundation

@testable import SionCore

let testArchiveGenerator = SionArchiveGenerator(
  name: "SionCoreTests",
  version: "unknown"
)

func testPNGData(width: UInt32 = 1, height: UInt32 = 1) -> Data {
  let encoded =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  guard var data = Data(base64Encoded: encoded) else {
    preconditionFailure("Invalid test PNG")
  }

  replaceUInt32(width, in: &data, at: 16)
  replaceUInt32(height, in: &data, at: 20)
  replaceUInt32(testCRC32(data[12..<29]), in: &data, at: 29)
  return data
}

func testPNGDataWithInvalidCompressedPixels() -> Data {
  var data = testPNGData()
  let imageDataChunkTypeOffset = 37
  let imageDataOffset = imageDataChunkTypeOffset + 4
  let imageDataLength = Int(readUInt32(data, at: imageDataChunkTypeOffset - 4))
  let checksumOffset = imageDataOffset + imageDataLength

  data[imageDataOffset] = 0
  replaceUInt32(
    testCRC32(data[imageDataChunkTypeOffset..<checksumOffset]),
    in: &data,
    at: checksumOffset
  )
  return data
}

func testDynamicPNGData() -> Data {
  let encoded =
    "iVBORw0KGgoAAAANSUhEUgAAABEAAAARCAIAAAC0D9CtAAADfUlEQVR4nAXBBViUZwAA4A+u/v6/v+uC7jgOjiMOjoPj4Dg4Do5ujhYkVNCpbE63GQtd6UJXutCVLnSlC13pQle6cum6+1m/LwAAmHQxlDFWQHVmQp9IGzJYY55gKpIRj4b6rVhDPN6SRHSnktEMaiKbnrVDQBpieCRWw3UJlD6dMdh5o0sylatItQWtj8MiiXhXCjGYTo5nUTO59IIDLjoZoGKx8aQuDepzOUOhaCxTTD4zErShzQlYZzI+kEaMZZLTOdR8Hr22AG5wMVtKWJBK63JYvVMwuGVjlWaqsyJN8WhHEtafio9mEEuzyRV2ak0+vb4Qbi5mtrnZHR4OFPD6UslQqRoDFlM4DmlPRPtSsJF0fCqLWJ5LrnZQFzrpTUVwaymzvZzd5eX2+HjgVQy1ZmOjzdSWgPQmo8Np2GQmviyHOC+PXFdAbXTRV5TAa8uYnRXs7ipun58/EBBAyGpsjTf1JCFDqeiSDGwuG19lJy7IJy8ppC4vpq9xwxs9zG2V7N5qbn8tfygoHAmJoDvRFE1BJtLR2SxsZS5+voO42EleVkRdXUrfUA5v9TJ3+dj7a7iDdfzhBuFYWDwRkcB4GjKTiS7kYIt5+EUFxKUu8qoS6voy+pYKeGcVc5+ffTjAPVHPH20UjjeLp1qlMx0ymM9G19qxDfn4lkLiymLyOjd1s4e+oxLeW808VMs+HuSeCfEvNgknW8TT7dLZLvlcrwLWO7DNTnxbEbGjlLypnLrdS9/jgw/WMI/VsU83cC+E+Vcjwltt4vud0qc98tf9yk9RFWx14dtLiF1l5J4K6u4q+gE/fDTAPFXPPt/IvdLMv9kqvNchftItfdUn/zio/DGs/jemgZ1uYreH3FdJHaimH6mFTwaZ50Lsy03cGy38u+3Cx13il73SDwPy70PKv6OqYUIjpsxgr5fc76MO1dBH6uCzDcxLYfb1CPdOG/9Rp/BFj/h9v/RbVP5nRNGPq/ikxk6blTkLOOinDgfoY/XwRCPzWjP7div3YQf/ebfwXZ/466D097CsG1OwJSqzVJNnzbbllpQFKzgapI+H4Kkm5kwL+0E791kX/22v8MuA+NeQFDsqoxMKnFKlGc26zJw8b8laZc1fYwMnw/B0hDnbxp7r5L7p4X/uF/6MijEjEjIu05OKOK1a5rSkFebMlRbHamvxoq1iXdz/3y7w8Tf9g7YAAAAASUVORK5CYII="
  guard let data = Data(base64Encoded: encoded) else {
    preconditionFailure("Invalid dynamic PNG")
  }

  return data
}

private func replaceUInt32(_ value: UInt32, in data: inout Data, at offset: Int) {
  data[offset] = UInt8((value >> 24) & 0xFF)
  data[offset + 1] = UInt8((value >> 16) & 0xFF)
  data[offset + 2] = UInt8((value >> 8) & 0xFF)
  data[offset + 3] = UInt8(value & 0xFF)
}

private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
  UInt32(data[offset]) << 24
    | UInt32(data[offset + 1]) << 16
    | UInt32(data[offset + 2]) << 8
    | UInt32(data[offset + 3])
}

private func testCRC32(_ data: Data.SubSequence) -> UInt32 {
  let polynomial: UInt32 = 0xEDB8_8320
  var checksum = UInt32.max

  for byte in data {
    var value = (checksum ^ UInt32(byte)) & 0xFF
    for _ in 0..<8 {
      value = value & 1 == 1 ? polynomial ^ (value >> 1) : value >> 1
    }
    checksum = value ^ (checksum >> 8)
  }

  return checksum ^ UInt32.max
}
