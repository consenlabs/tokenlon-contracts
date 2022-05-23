interface GetAddressFunc {
    getAddress(): Promise<string>
}

interface GetAddressProp {
    address: string
}

export type Addressable = GetAddressFunc | GetAddressProp | string

export async function getAddress(target: Addressable): Promise<string> {
    if (typeof target == "string") {
        return target
    }
    if ("address" in target) {
        return target.address
    }
    return target.getAddress()
}
