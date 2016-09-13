import numpy as np

featDim = 224 * 224 * 3
labDim = 1000
totalCount = 16 * 100

def createFakeData(count):
    features = np.random.randn(count, featDim)
    labels = np.random.randint(0, labDim, size=(count, 1))
    return features, labels

f, l = createFakeData(totalCount)

np.savetxt(r'./imagenet_data0.5K.txt', np.hstack((l, f)), fmt='%d' + ' %f4' * featDim)

