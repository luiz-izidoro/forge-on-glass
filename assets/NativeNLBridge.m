#import <Foundation/Foundation.h>
#import <NaturalLanguage/NaturalLanguage.h>
#include <stdint.h>

// The bridge intentionally uses NLEmbedding's native float buffer API. It
// avoids NSArray<NSNumber *> and NSData ownership/bridging in the Swift guest.
static NSString *RadarEmbeddingError = nil;

static NLEmbedding *RadarSentenceModel(void) {
    NLEmbedding *model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguagePortuguese];
    if (model == nil) model = [NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish];
    return model;
}

int32_t radar_native_embedding_available(void) {
    RadarEmbeddingError = nil;
    NLEmbedding *model = RadarSentenceModel();
    if (model == nil) RadarEmbeddingError = @"no Portuguese/English model installed";
    return model != nil ? 1 : 0;
}

int32_t radar_sentence_embedding_dimension(void) {
    RadarEmbeddingError = nil;
    NLEmbedding *model = RadarSentenceModel();
    if (model == nil) {
        RadarEmbeddingError = @"no Portuguese/English model installed";
        return 0;
    }
    return (int32_t)model.dimension;
}

// Returns 1 and writes count doubles when the system model accepts the text.
// The output buffer belongs to Swift and is never retained by Objective-C.
int32_t radar_get_sentence_embedding(NSString *text, double *output,
                                     int32_t capacity, int32_t *count) {
    RadarEmbeddingError = nil;
    if (count != NULL) *count = 0;
    if (text == nil || text.length == 0 || output == NULL || count == NULL) {
        RadarEmbeddingError = @"invalid input buffer";
        return 0;
    }
    NLEmbedding *model = RadarSentenceModel();
    if (model == nil) {
        RadarEmbeddingError = @"no Portuguese/English model installed";
        return 0;
    }
    NSUInteger dimension = model.dimension;
    if (dimension == 0 || dimension > (NSUInteger)capacity) {
        RadarEmbeddingError = @"embedding dimension exceeds output buffer";
        return 0;
    }
    float *values = calloc(dimension, sizeof(float));
    if (values == NULL) {
        RadarEmbeddingError = @"could not allocate embedding buffer";
        return 0;
    }
    BOOL ok = [model getVector:values forString:text];
    if (ok) {
        for (NSUInteger i = 0; i < dimension; i++) output[i] = (double)values[i];
        *count = (int32_t)dimension;
    } else {
        RadarEmbeddingError = @"model returned no vector for text";
    }
    free(values);
    return ok ? 1 : 0;
}

NSString *radar_native_embedding_error(void) { return RadarEmbeddingError; }
