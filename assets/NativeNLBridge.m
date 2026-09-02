#import <Foundation/Foundation.h>
#import <NaturalLanguage/NaturalLanguage.h>

# Bridge diagnostic (2026-09-02): the first IPA executed the embedding model
# during viewDidLoad and copied NSData directly into an Array, making launch
# fragile on the device. The canonical fixture now runs on explicit user action,
# uses a stable withUnsafeMutableBytes copy, and reports nil/error visibly.
// explicit return values; it deliberately does not use @try/@catch because the
// arm64e SDK profile does not provide the NSException EH type to the linker.
static NSString *RadarEmbeddingError = nil;

NSData *radar_sentence_embedding(NSString *text) {
    RadarEmbeddingError = nil;
    if (text == nil || text.length == 0) {
        RadarEmbeddingError = @"empty text";
        return nil;
    }
    NLEmbedding *model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguagePortuguese];
    if (model == nil) model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish];
    if (model == nil) {
        RadarEmbeddingError = @"no Portuguese/English model installed";
        return nil;
    }
    NSArray<NSNumber *> *values = [model vectorForString:text];
    if (values == nil || values.count == 0) {
        RadarEmbeddingError = @"model returned empty vector";
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:values.count * sizeof(double)];
    double *result = (double *)data.mutableBytes;
    for (NSUInteger i = 0; i < values.count; i++) result[i] = values[i].doubleValue;
    return data;
}

BOOL radar_native_embedding_available(void) {
    RadarEmbeddingError = nil;
    BOOL portuguese = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguagePortuguese] != nil;
    BOOL english = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish] != nil;
    if (!portuguese && !english) RadarEmbeddingError = @"no Portuguese/English model installed";
    return portuguese || english;
}

NSString *radar_native_embedding_error(void) { return RadarEmbeddingError; }
