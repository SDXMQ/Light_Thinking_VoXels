{
    if (gl_LocalInvocationIndex == 0u) {
        isActive = (gl_WorkGroupID.x + gl_WorkGroupID.y + gl_WorkGroupID.z + frameCounter) % max(1, SDF_UPDATE_INTERVAL);
    }
    barrier();
    memoryBarrierShared();
    for (int k = 0; k < 2; k++) {
        int index = int(gl_LocalInvocationIndex + k * 512);
        if (index > 1000) break;
        ivec3 currentLocalCoord = ivec3(index%10, index/10%10, index/100%10) - 1;
        ivec3 texCoord = currentLocalCoord + baseCoord;
        int thisLocalOccupancy = imageLoad(occupancyVolume, texCoord).r;
        ivec3 prevTexCoord0 = texCoord + (1<<j) * floorCamPosOffset;
        ivec3 prevTexCoord = prevTexCoord0 + ivec3(0, (frameCounter % 2 * 2 + j/4) * voxelVolumeSize.y, 0);
        if ((thisLocalOccupancy >> j & 1) == 1) {
            fullDist[currentLocalCoord.x+1][currentLocalCoord.y+1][currentLocalCoord.z+1] = (1.0-1.0/sqrt(3.0)) / (1<<j);
        } else if (
            all(greaterThanEqual(prevTexCoord0, ivec3(0))) &&
            all(lessThan(prevTexCoord0, voxelVolumeSize))
        ) {
            fullDist[currentLocalCoord.x+1][currentLocalCoord.y+1][currentLocalCoord.z+1] = imageLoad(distanceFieldI, prevTexCoord)[j%4] + 1.0 / (1<<j);
        } else {
            atomicExchange(isActive, 0);
            #if j > 0
                float prevDist = 10000.0;
                ivec3 prevCoord = prevTexCoord0 / 2 + voxelVolumeSize / 4 + ivec3(0, (frameCounter % 2 * 2 + (j-1)/4) * voxelVolumeSize.y, 0);
                ivec3 prevFractCoord = prevTexCoord0 % 2;
                for (int k = 0; k < 8; k++) {
                    ivec3 offset = ivec3(k%2, k/2%2, k/4%2) * (2 * prevFractCoord - 1);
                    vec3 distOffset = (0.75 - 0.5 * vec3(k == 0)) / (1<<(j-1));
                    prevDist = min(
                        prevDist,
                        min(min(distOffset.x, distOffset.y), distOffset.z)
                        + imageLoad(distanceFieldI, prevCoord + offset)[(j-1)%4]
                    );
                }
                fullDist[currentLocalCoord.x+1][currentLocalCoord.y+1][currentLocalCoord.z+1] = prevDist + 1.0/(1<<j);
            #else
                fullDist[currentLocalCoord.x+1][currentLocalCoord.y+1][currentLocalCoord.z+1] = 1000.0;
            #endif
        }
    }
    barrier();
    memoryBarrierShared();

    theseDists[j] = (thisOccupancy >> j & 1) == 1 ? -1.0/sqrt(3.0) / (1<<j) : 1000;
    if (isActive == 0) {
        #if j > 0
            ivec3 prevTexCoord0 = texCoord + (1<<j) * floorCamPosOffset;
            ivec3 prevCoord = (prevTexCoord0) / 2 + voxelVolumeSize / 4 + ivec3(0, (frameCounter % 2 * 2 + (j-1)/4) * voxelVolumeSize.y, 0);
            ivec3 prevFractCoord = prevTexCoord0 % 2;

            float prevDist = 10000.0;
            for (int k = 0; k < 8; k++) {
                ivec3 offset = ivec3(k%2, k/2%2, k/4%2) * (2 * prevFractCoord - 1);
                float distOffset = (0.75 - 0.5 * float(k == 0)) / (1<<(j-1));
                prevDist = min(
                    prevDist,
                    distOffset
                    + imageLoad(distanceFieldI, prevCoord + offset)[(j-1)%4]
                );
            }
            if (prevDist < (levelFadeDist*1.5)/(1<<j)) {
            #endif

            // 3-axis separable filter for 3D min reduction (27-tap -> 9-tap)
            float minXYZ = 10000.0;
            for (int dz = 0; dz < 3; dz++) {
                float minY = 10000.0;
                for (int dy = 0; dy < 3; dy++) {
                    ivec3 baseC = localCoord + ivec3(0, dy, dz);
                    float minX = min(fullDist[baseC.x][baseC.y][baseC.z],
                                 min(fullDist[baseC.x + 1][baseC.y][baseC.z],
                                     fullDist[baseC.x + 2][baseC.y][baseC.z]));
                    minY = min(minY, minX);
                }
                minXYZ = min(minXYZ, minY);
            }
            theseDists[j] = min(theseDists[j], minXYZ);

            #if SDF_UPDATE_INTERVAL == 0
                float minXYZ_ext = 10000.0;
                for (int dz = 0; dz < 3; dz++) {
                    for (int dy = 0; dy < 3; dy++) {
                        for (int dx = 0; dx < 3; dx++) {
                            ivec3 c3 = localCoord + 2 * ivec3(dx, dy, dz) - 1;
                            if (all(greaterThanEqual(c3, ivec3(0))) && all(lessThan(c3, ivec3(10)))) {
                                minXYZ_ext = min(minXYZ_ext, fullDist[c3.x][c3.y][c3.z] + 1.0/(1<<j));
                            }
                        }
                    }
                }
                theseDists[j] = min(theseDists[j], minXYZ_ext);
            #endif
            #if j > 0
                if (prevDist > levelFadeDist/(1<<j)) {
                    theseDists[j] = mix(theseDists[j], prevDist, prevDist * (1<<j) / (0.5 * levelFadeDist) - 2.0);
                }
            } else {
                theseDists[j] = prevDist;
            }
            const float edgeDist = 4.0;
            float edgeDecider = min(infnorm(max(abs(texCoord + 0.5 - 0.5 * voxelVolumeSize) + edgeDist + 0.5 - 0.5 * voxelVolumeSize, 0.0)) / edgeDist, 1.0);
            if (edgeDecider > 0.01) {
                theseDists[j] = mix(theseDists[j], prevDist, edgeDecider);
            }
        #endif
    } else if (theseDists[j] > 0.0) {
        theseDists[j] = fullDist[localCoord.x+1][localCoord.y+1][localCoord.z+1] - 1.0/(1<<j);
    }
    barrier();
}
