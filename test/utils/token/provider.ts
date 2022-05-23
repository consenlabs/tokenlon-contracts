import { Provider } from "@ethersproject/abstract-provider"

let p: Provider

export function getProvider(): Provider {
    if (!p) {
        throw new Error("No provider set")
    }
    return p
}

export function useProvider(provider: Provider) {
    p = provider
}

export function useProviderIfNotExisting(provider: Provider) {
    if (!p) {
        p = provider
    }
}
