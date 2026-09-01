#import <Foundation/Foundation.h>
#import <NaturalLanguage/NaturalLanguage.h>

// Native iOS 26.5 NaturalLanguage bridge for Swift projects built in iSH.
// Compiled by ios-swift-builder with Clang 21 and linked on demand.
NSData *radar_sentence_embedding(NSString *text) {
    if (text == nil || text.length == 0) return nil;
    NLEmbedding *model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguagePortuguese];
    if (model == nil) model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish];
    if (model == nil) return nil;
    NSArray<NSNumber *> *values = [model vectorForString:text];
    if (values.count == 0) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:values.count * sizeof(double)];
    double *result = (double *)data.mutableBytes;
    for (NSUInteger i = 0; i < values.count; i++) result[i] = values[i].doubleValue;
    return data;
}

BOOL radar_native_embedding_available(void) {
    return [NLEmbedding sentenceEmbeddingForLanguage:NLLanguagePortuguese] != nil || [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish] != nil;
}
