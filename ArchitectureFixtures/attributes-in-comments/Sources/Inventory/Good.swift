/// Never use @_silgen_name here: it reaches C without an import.
/* @_cdecl and @_extern are banned too. /* Nested, as Swift allows. */ */
public let bannedAttributes = ["@_silgen_name", #"@_cdecl"#, """
    @_extern
    """, "\("@_cdecl")"]
