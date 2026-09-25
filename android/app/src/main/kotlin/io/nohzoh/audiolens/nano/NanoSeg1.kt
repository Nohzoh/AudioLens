package io.nohzoh.audiolens.nano

import com.google.mlkit.genai.schema.annotations.Generable
import com.google.mlkit.genai.schema.annotations.Guide

// #434: typed output of the Nano cascade's segment 1 (ML Kit structured
// output), so the title no longer depends on the model following the
// "[Title]" text convention. Kept in its own package so the ProGuard keep
// rule for it (and the schema KSP generates next to it) stays one line.
@Generable("Opening of a spoken audio guide commentary about a photographed place or artwork")
data class NanoSeg1(
    @Guide("Short title naming the place or artwork, 3 to 6 words, no brackets")
    val title: String,
    @Guide("The spoken description of what the photo shows, without an introduction sentence and without repeating the title")
    val text: String,
)
