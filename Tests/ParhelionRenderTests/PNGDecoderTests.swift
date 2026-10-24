import Foundation
import Testing

@testable import ParhelionRender

/// A PNG made by Python's `zlib` and `struct`, so that its deflate data
/// comes from a real encoder, with dynamic Huffman blocks, and the FNV-1a
/// hash of the RGBA pixels that decoding it must give.
private struct Vector: CustomTestStringConvertible, Sendable {
    var name: String
    var width: Int
    var height: Int
    var hash: UInt64
    var base64: String

    var testDescription: String { name }
}

/// FNV-1a, 64 bits.
private func fnv(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
        hash ^= UInt64(byte)
        hash = hash &* 0x100_0000_01b3
    }
    return hash
}

// Each image's rows cycle through the five filters. The names give the
// color type and bit depth; `Key` images have a tRNS color key, palette4
// has a tRNS alpha table, the adam7 images are interlaced, and stored is
// compressed at level 0.
private let vectors: [Vector] = [
    Vector(
        name: "rgba8", width: 24, height: 20, hash: 0xb04db49bca927f0d,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABgAAAAUCAYAAACXtf2DAAACGElEQVR42l3Uf0zUdRzH8TcqX/W40uwqTWOa"
            + "VERmRo5JfSqjAtIitLPl+QNMpBwX1bH0Y05ayNIhCpo7Z2GSc4pklvaxTS2mZkpiVsxVKHPOH1eLMgttmaY9"
            + "gTf/dNtj+97nvp+7z/den9dHhJdPnvACssKfKMcGJEvSwFR5KdHIp0mZcjUlV7JHhWR5WoEcNcUyPMNKOLtM"
            + "tudUypVgVLJCtVKdXy8thU5uDTdIUaRRnG2Wf0tbJbM8JlUVceJf5fkkqAJ4DDVoxSFsxj4cwXq9NngSYQzB"
            + "aDj9jn0697POuT06fkD8c/Ah/kYJ9mICWvEwRmI7TiAB96Mv9iELGzANL+ILRDADYa+nDNzij/dqvHhvMd5G"
            + "b8SQgdlYjrEYgQO4D/8gis8xC0GcQxPWYhlCuM7r1fkEEsLdOAdWIHWIxyS1BjswEIN17DYEcQEpWIqx4B+Q"
            + "WfqepxbTnugzCUkB05aSaIpGJZumtFRTYow5lZFpSrJzzcKckCkKFpi2ULEZn29NU2GZmRmuNO2RqOlpa017"
            + "ab0pKnemqaLBjK9uNG3RZlNS02oWrouZkro4ya5I8klvr0sCeuIm9MN8tQgbsQQlmIuPcAl34cD/5v+Aqs65"
            + "GnIUy2HRhIl4Cuc15AYNtRrDcRQ36Ca4AzEMQzJ24XksQAEhp9UNjvd+IZAdnaHEe2kYg+FYiFycxYNYgz9x"
            + "Hlm4R8OPYCsG4U63svYAAAIZSURBVDCG4gOM7w55M0aAFcllDa8XhuBjjAMrlqH4FaexRwNeiYhuhKkI6Bhb"
            + "WL6GjRmffSQjYNdnJ9olOcl2WzDVvhYytk9+pv2pMNdOD4fspkiBrbTF9pNSa18vL7PXVFTaE9VRmxettdGa"
            + "evvHOmddXYOdv6XR9nDN9szOVvvc7phdtT9Oyhdk+CSDQB5CGgYggpHIwVGv6/P3sAHb0IzDOIuD2IsG/IVU"
            + "TMS1nd+hId+MrRiFU5iO38Aj+1/GNrSgD4pQiMcR0CYf1ObW4hltfkezNxNy8P2UroCr8DMO4mlt8XEN8YK2"
            + "fCW+1+tJOIn+eFNPgG91bK6Gntkd8jeqXZu6Fnfieh0vRR766z09wBPLTGzEs6jCGDygzb6IJLiWkM8tyg+4"
            + "YYWJbko42c2OpLo3rHETSjPdlPJc17ci5DZWF7g90WLXVmPdxXVl7ve6Svfdlqhb4mpd+s56l7XbuRn7G9z8"
            + "Q41udnOzy/ux1d17POZ2nY6T3a/k+2Q1gUzGRTVZ7cA8HZunYx33puvYINU9r0Xfp+v9q7tDPoml2uSO4/p2"
            + "DbUj5DxtLoefnx74+Qv9Z/EqjmiTV+AWNOJRpOErjCDkyLvp8d40AhmNAszAVdyoDe2ngYuG+CWO6ZF9BZdw"
            + "BpcxVU+EFzAd47pDXoZNGhIrkHf0eo62tB5vadhsSfFBtK2sXtjmdEDoUtfckM6d4/0HoHOAv2aro1UAAAAT"
            + "dEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElFTkSuQmCC"
    ),
    Vector(
        name: "rgb8Key", width: 20, height: 16, hash: 0x70cc17391bef68bd,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABQAAAAQCAIAAACZeshMAAAABnRSTlMAAAD/AADQPjN8AAABnElEQVR42iWS"
            + "YWgbZRyHf23l3Tv6yn8f6sh0hLmeGN0ag5Qxy03iMHR6qExOPzRly1j9EJIPsmG9rtkQrASc4E3lBuOGFdt4"
            + "QhWX3WYHrnbLwUZ74Ax+SJd82G1hyuoicRsiTLd7W/h/eeB9eOHhBzyAeAWRz6DUkVAQ4q6z0B8gswv5YxIn"
            + "emHmYZ+B87/EeRP+Emqb0cyhA8dJ6JDXg8ZMW+0n0YDwIWYwabSNTSSmIDwIFSNq2y2Q2AjRD+Ei9kG7M5Qx"
            + "SviOQjPRHcVFwm5Cg0IzfyiKM4RrhG4KTWdDFB5hkFCi0Gyq0S58H2U2bx2oK14fW8PZTc528nKqnmF9LMnZ"
            + "Vs4u8dH36natj1mcnefsHT4wVa+d7WOL/JHw57tXvMiPKv4DKoCD2Vue/q6Kn4GTwDkUCp65pOJt4ClAR/Ky"
            + "519VcQpIQjYQ3VpkWVNyWmJRk8FuaPpBLfOhls9JnNA0c1Gz92vOHYnzdzQ/p9UWtaamdeDjIbEG8rrRGC6p"
            + "c0OCIMblTe4oGe0hcRTiIMT7GDlRctcNiS0Ql+T7dX9/8gAAAZxJREFU2D+llWAW4RiFZuJAFm8SXiPcpdDM"
            + "8yzWEkxCL4Wm82w2DImnCTcpNJtqtgvOy+wWb82Zim2wbZxt56yXl782MxcM1uJsB2cn+eht015vsEHOnpMJ"
            + "B2JmbdlgG1aD/TAWiRXRAO7LJLMzY/r9In4BXgUeQ+HPMXNTES3gAnAPyakx/6cifGB4NdhLVmTKUo5aibIl"
            + "g3FL/93K7LHy30qcOG2Zhyz7Ucu5JnHesvy2VXOt5rjVgcPTYifEixDb0PDT6uy0iEO8DnEVk3+njda0KEGU"
            + "IaoY+SPt/jYtFiAuQswhdj29EuxxwikKzcQzLvYQbhOGKTTznS6WCJyQo9B0trjoWVnYAoVm03W78FWWneOt"
            + "XErZWmELnL3BWZaXT6Qyn1TYPc4+5+wLPvp8ylYq7C3OrnO2jg98lKp5FXZlNdj5eCSohtvCE8CXmPXiulHF"
            + "DeAIsBeFnrh5vIpOyFXtR7I/7m+u4lNg+2qwYhB5MlDSQSIbyGC7Az0dZNYG+W8kTiwH5r+B/Vfg/Cpx/oXA"
            + "Hwxq+4LmePAQi95Qi1ZMUyoAAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElFTkSuQmCC"
    ),
    Vector(
        name: "gray1", width: 19, height: 9, hash: 0x546caf1d3f149919,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABMAAAAJAQAAAAD4ZiqcAAAAFklEQVR42mMIDXVgXMXwjWn16gXMDdraLKsZ"
            + "gSG5cgAAABdJREFUXjOsWrWAMZThNVNoaAIzw7VjAOLUDNdpAA7BAAAAE3RFWHRDb21tZW50AHRlc3QgdmVj"
            + "dG9y8aZwzQAAAABJRU5ErkJggg=="
    ),
    Vector(
        name: "gray2", width: 17, height: 7, hash: 0x1442d86d5bf56089,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABEAAAAHAgAAAACBOeEBAAAAFUlEQVR42mOQBgIGxhwGBoYrTK5A4MCcx83O"
            + "AidrAAAAFklEQVTNLcsSChR5ypADBA6MG4Hs8wCUMAhigKztAAAAABN0RVh0Q29tbWVudAB0ZXN0IHZlY3Rv"
            + "cvGmcM0AAAAASUVORK5CYII="
    ),
    Vector(
        name: "gray4Key", width: 15, height: 9, hash: 0xfe54e2b12f12c048,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAA8AAAAJBAAAAAANFMSKAAAAAnRSTlMAB+j3WJsAAAAoSURBVHjaY2CAAkZG"
            + "JTAQZmJUdk2vnL33ATOTa1h4ReUkWRZGZdOOCsa9lgzpYRRjAAAAKUlEQVSs6z0f96ofTGBk23Nmz549ZzYB"
            + "FZuGd64GKmadtHjL3nP33wAABIMbEOp1KR0AAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElF"
            + "TkSuQmCC"
    ),
    Vector(
        name: "gray8", width: 21, height: 13, hash: 0x7228900ce529b468,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABUAAAANCAAAAABj+Xq8AAAAlElEQVR42gEeAeH+AABJktskbbb/SJHaI2y1"
            + "/keQ2SJrtAGXVFQURJzczKzE1KTEPExsHDS0VMQCl3at+HPCUdw/LrXgCzoJxEemXWjDA66ciJMH5kJpkUAs"
            + "xzP6lr1lVPDLnwSXWi3ww6gFVVWduRgbVSVU9SqNQHMA8wvra8tz43ODa+tLy2PzA/Nry0vrAYoHBwsDFw97"
            + "P7k0yAAAAJVJREFUe4eni3N3r/srxwcLAwKXlpF4y1JN9D++CZAj2hXcJ+YhKLsDqOq5ETY4I4NQ7j2d8vRH"
            + "LyxysRnOBJesLNz8VAQcsEoVIOzkwfWUcp1cFADmQaSLsnUI516pjLN6DeBflvG0ewIBfUI+NhJyLk7aQp6m"
            + "stLO7srCvvYyApcasTDjXu1cb7LZCGtmRRRHymGgU6uChu2Mkia3AAAAE3RFWHRDb21tZW50AHRlc3QgdmVj"
            + "dG9y8aZwzQAAAABJRU5ErkJggg=="
    ),
    Vector(
        name: "gray16", width: 11, height: 9, hash: 0x0e92ce7e512a54e8,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAsAAAAJEAAAAACRn1WyAAAAbUlEQVR42gHPADD/AAAASUqSlNveJChtcra8"
            + "//9IUJGa2uQBl5dUVVRVFBVERZyd3N3MzaytxMXU1QKXl3Z2ra34+HNzwsJRUdzcPz8uLrW1A66unJ2IiJOU"
            + "Bwfm50JCaWqRkUBBLCwEl5daWi0u8PDD0EBRiwAAAG1JREFUw6ipBQZVVlVWnZ65uQDz8wsM6+1rbsvPc3jj"
            + "6XN6g4trdOv1AYqKBwgHCAsMAwQXGA8Qe3x7fIeIp6gCl5eWlpGReHjLy1JSTU309D8/vr4KCQOoqOrquboR"
            + "ETY3ODgjJIODUFHu7j2+RfxigfN5ArMAAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElFTkSu"
            + "QmCC"
    ),
    Vector(
        name: "palette4", width: 13, height: 11, hash: 0x16a577bdf0e9fa49,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALBAMAAABWnBpSAAAAMFBMVEUA/wAQ9h8g7T4w5F1A23xQ0ptgybpw"
            + "wNmAt/iQrhegpTawnFXAk3TQipPggbLweNH8LCRcAAAABHRSTlMAgP9At17B+AAAACNJREFUeNpjYFR2Te9c"
            + "fYBRWQkEhJnAlJICsyuIElJgAVNKsgyrz74X9fZaAAAAI0lEQVQHKk1gPAvkKSlJMoEpoLousHppFog+YQaQ"
            + "aWffMwAA5ZUR06o6XYAAAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElFTkSuQmCC"
    ),
    Vector(
        name: "palette8", width: 16, height: 16, hash: 0x57a478024c7a0065,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAAMFBMVEUA/wAQ9h8g7T4w5F1A23xQ0ptgybpw"
            + "wNmAt/iQrhegpTawnFXAk3TQipPggbLweNH8LCRcAAAAT0lEQVR42l2OiQ6DMAxDkzZNT8r//2c5SiGsjCFt"
            + "syxZkZIXA/wJAX+lAJUmw3atW9sPOTUorYmmg9ku/QDp2ijEVIhi6QOACSP5rN2gbEKOCMzzO6n1XQAAAFBJ"
            + "REFU5fmTN3Tixfkt3lAz8WwXt2JVm25E91uxUENNNVeAQNmpxE8ixNa+/YYWw8vqn6a296tB6bYnc4hc0O5Z"
            + "JEsTkRNgzEOKwTvLhrTCF7xvSarAlyMEAAAAE3RFWHRDb21tZW50AHRlc3QgdmVjdG9y8aZwzQAAAABJRU5E"
            + "rkJggg=="
    ),
    Vector(
        name: "grayAlpha8", width: 18, height: 12, hash: 0xdb8faa9f4112b88d,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAABIAAAAMCAQAAADFGyU3AAAA0UlEQVR42hXPT0iTcRwG8GfOeIrRE0lR0HsI"
            + "VgTL7FDIiLQasvWfirdLh4JJh5jC2EijcBcPRu7gSjYY6knsDewPhgMPBdkLQosOo0vTwwuFQcpLNYOoqH7y"
            + "hS/fy/fh8wA4pfvWYmRPtDdesf8lT6YLuXo+XO5xZit/3URtxPvgB0qwZWubujSmJb3VtFy916TZR3VWPbJ0"
            + "WE0l9OExfiKLeVzEEo6hDbPwEMIRbIKLBKYQfIIx3uUDksuM8QYLPM5WLvAQf7HIF7xOm80lXMEBfMVrOMmQ"
            + "Hu4AAADSSURBVNiAy2bGMYed2GWuvbDxAxGggZBWrFSkGs3GP9rZ5GA6lVvJnylXne5Kww3WGl7KD9wDRYUU"
            + "1A5t0R0zQ3qoYWXVr6f6rf1aWIcXUcAtVHEJ57Bm4C8NeARh1LHdFNmHZQQdfOEct7KdUYY5yAv02cFxfuca"
            + "EzxoSmTW4dNoNR9/DLIZFp7htEnYjVV8wivDHkUGJuyEJq3hyEz0Znyj/Tl5Nf0ol88/L992Nlc891qt6H3z"
            + "AwOIqVPtalFGbTqvumKa0JRmVNM7+Xqjef0HHDeJC+Tv0XsAAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3Lx"
            + "pnDNAAAAAElFTkSuQmCC"
    ),
    Vector(
        name: "grayAlpha16", width: 9, height: 7, hash: 0x6c2f6336aa1e6cce,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAkAAAAHEAQAAAAgAnOoAAAAV0lEQVR42i3OoQrCQBzH8b9OWTBcEWxLVt9g"
            + "IIhBo6Dl3kDEdCADo0VsKsyyBzCoafgAGjWtuiZYLAcWm34PdvC59OPuK8LpSxBsJAwfonVTomgqcXyWNP1J"
            + "lvUA9rE0AAAAV0lEQVTE2tKO0ZCRU0cXCXLccUDZjWY44guDCwbI0YZ34kpEqSW28PFCB2OsUXEvabRgccUe"
            + "VYwK8kGNf9+ETwi/EW4IfxJuCF+48BUjn5Hjxh4aUJgX/qJBM50hNd8kAAAAE3RFWHRDb21tZW50AHRlc3Qg"
            + "dmVjdG9y8aZwzQAAAABJRU5ErkJggg=="
    ),
    Vector(
        name: "rgba16", width: 10, height: 8, hash: 0x44d31c6be5e25fa1,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAoAAAAIEAYAAACQarL1AAAAw0lEQVR42l3RMUgCURwG8H+Z3KBog2Dg0OKq"
            + "tNWmiNQ5CCkKIjSHiBBIIbgIDj4iiCvQRSHCwUGtSV4EElaTLrU0eEMgSOAieJHUYPfuG8Ju+fHdu/+7x/uI"
            + "jGexcB4RhULanved6OLi43x3n2g4VN8OHojc7pfN4y2iTOb58OyKqNO5u6mvi6nW132BSJavfa9TIkUpl1aI"
            + "XIlKBRvGYp8y1OQNXYdDM3Iw+GnkahVZVbE+GCA3m5h7etLkVWwoTulKnJzAVguteCsFAAAAw0lEQVTO5zCb"
            + "hb0ejESgqkKfD3q9RCai7dt2u1Cw7tia1epPXcjYt9vKbc3LS109S5L+Xs/jMXIggPVUCllRMOf3f7vX/k5I"
            + "lExCjwdOp/DxETYa0GyG8fiytZoB47OZuEPGLRZRCuOTiSiF8XRalMJ4vy9KYTybFaUwPhqJUkQWpTBeLIpS"
            + "xPdGKfX101OUIkm4XEnCpes/MLLJhFKcTmS7Hev5PHI+j7lS6V8p5TJUFJjLwX4fRqMwHIaatlxKt0v0C6Cj"
            + "zTbP0BOxAAAAE3RFWHRDb21tZW50AHRlc3QgdmVjdG9y8aZwzQAAAABJRU5ErkJggg=="
    ),
    Vector(
        name: "adam7", width: 13, height: 11, hash: 0xbe8f5fd038389b92,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAA0AAAALCAYAAAHTtTf3AAAAzUlEQVR42i3QT0hUURQG8O81Ijm4u8LbBEXq"
            + "S4TuxggGIigkFZ9I5J/Ng0lw4aIgxtq0kNnMKihGBhxIXImgI4IIwyxiCAlxIVwGBhdZ0GJ4ikhEEBUtvr4Z"
            + "Z/Hj3nMPl/NxAIBFjNJDpaLLVSBEHxt4Ri+sfGi20IEoYoi6OgXpAQIsM4Myq/hML4jK6s6r8xJXEA0D0bxM"
            + "qbCWgb1gaJPM2Kcs2gNWbZ0Nu8wEFhezxn6FsdMyJn+lX263JipYVbrlnsyIle+AwRhTOGEaz5kD4wdtJgAA"
            + "AM5JREFUWUKeNfTSM3aOAc4Vb0v22wabQQb0e0FuSEXO5A8SyWgia3wPxp+TXfklXQpgDzXsoXyTomQuTxM/"
            + "YCp+w3T8irn4lKV4k7V4T/vzV2gwhUs9Miyr8kWOZFs+SV3WW/fmhhREK7PH8qJ9an12R0ZlSe5IWT7KXSTw"
            + "OJ9N+q+R9E+kIGnZl3H5ISNy3q4LrbqjNQnX5L78lE5Zkw25KQftt7eiSXgkbpLG/WPgbjHlEgwdmXZPmHGz"
            + "zOm96N6x5N6z6n6z5obYcNf5H8oRqcoDrysDAAAAE3RFWHRDb21tZW50AHRlc3QgdmVjdG9y8aZwzQAAAABJ"
            + "RU5ErkJggg=="
    ),
    Vector(
        name: "adam7Gray2", width: 7, height: 5, hash: 0x806095d1da8e29a3,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAcAAAAFAgAAAAGRRoEzAAAAEElEQVR42mNgYGBgYWBYwLiAqYPhEL7nGAAA"
            + "ABBJREFUDmMJUwaj3z+maTMAM0QGCIa4OhsAAAATdEVYdENvbW1lbnQAdGVzdCB2ZWN0b3LxpnDNAAAAAElF"
            + "TkSuQmCC"
    ),
    Vector(
        name: "stored", width: 6, height: 4, hash: 0x05f245c047778685,
        base64:
            "iVBORw0KGgoAAAANSUhEUgAAAAYAAAAECAIAAAAiZtkUAAAAK0lEQVR4AQFMALP/AAAAYygAY1AAY3gAY6AA"
            + "Y8gAYwEAPGMoAAAoAAAoAAAoAAAo6ybhvgAAACxJREFUAAACADwAADwAADwAADwAADwAADwAAwB4MhQeABQe"
            + "ABQeABQeABQeALDyCSRxUNCdAAAAE3RFWHRDb21tZW50AHRlc3QgdmVjdG9y8aZwzQAAAABJRU5ErkJggg=="
    ),
]

@Suite("PNG decoding")
struct PNGDecoderTests {
    @Test("Every color type, bit depth, filter, and interlacing decodes", arguments: vectors)
    fileprivate func decodes(_ vector: Vector) throws {
        let data = try #require(Data(base64Encoded: vector.base64))
        let bitmap = try Bitmap(pngData: [UInt8](data))
        #expect(bitmap.width == vector.width && bitmap.height == vector.height)
        #expect(fnv(bitmap.pixels) == vector.hash)
    }

    @Test("Parhelion's own PNG encoder round-trips")
    func roundTrip() throws {
        var canvas = Canvas(width: 30, height: 20, scale: 2, background: .clear)
        canvas.fill(
            CGRect(x: 2, y: 3, width: 20, height: 10), color: RGBA(red: 10, green: 200, blue: 30))
        canvas.fill(
            Path(ellipseIn: CGRect(x: 10, y: 5, width: 15, height: 12)),
            color: RGBA(red: 250, green: 20, blue: 90, alpha: 128))
        let bitmap = try Bitmap(pngData: canvas.pngData())
        #expect(bitmap == Bitmap(canvas))
    }

    @Test("Damaged data fails with an error")
    func errors() throws {
        #expect(throws: Bitmap.PNGError.notPNG) { try Bitmap(pngData: [1, 2, 3]) }
        let data = try #require(Data(base64Encoded: vectors[0].base64))
        let truncated = [UInt8](data.prefix(data.count / 2))
        #expect(throws: Bitmap.PNGError.self) { try Bitmap(pngData: truncated) }
        var corrupted = [UInt8](data)
        // Flip bits in the middle of the compressed data.
        corrupted[corrupted.count / 2] ^= 0x5A
        #expect(throws: Bitmap.PNGError.self) { try Bitmap(pngData: corrupted) }
    }

    @Test("Halving averages blocks of pixels, weighting colors by opacity")
    func halving() {
        let bitmap = Bitmap(
            width: 3, height: 1,
            pixels: [255, 0, 0, 255, 0, 0, 255, 0, 10, 20, 30, 255])
        let half = bitmap.halved()
        #expect(half.width == 2 && half.height == 1)
        // The transparent blue pixel adds nothing to the color.
        #expect(half.pixel(x: 0, y: 0) == RGBA(red: 255, green: 0, blue: 0, alpha: 128))
        #expect(half.pixel(x: 1, y: 0) == RGBA(red: 10, green: 20, blue: 30))
    }
}
