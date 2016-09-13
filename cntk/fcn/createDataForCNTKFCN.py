import numpy as np

featDim = 26752
labDim = 26752 
totalCount = 64 * 100

def createFakeData(count):
    features = np.random.randn(count, featDim)
    labels = np.random.randint(0, labDim, size=(count, 1))
    return features, labels

f, l = createFakeData(totalCount)

np.savetxt(r'./data26752.txt', np.hstack((l, f)), fmt='%d' + ' %f4' * featDim)

