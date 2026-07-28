// Intra-warp Bitonic Sort (N <= 16) - Executed in lockstep within subgroup without inter-step barriers
if (participateInSorting) {
    // N>1
    flipPair(index, 0);

    // N>2
    flipPair(index, 1);
    dispersePair(index, 0);

    // N>4
    flipPair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);

    // N>8
    flipPair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);

    // N>16
    flipPair(index, 4);
    dispersePair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);
}
barrier();

// Inter-warp Bitonic Sort (N > 16)
// N>32
if (participateInSorting) { flipPair(index, 5); }
barrier();
if (participateInSorting) { dispersePair(index, 4); }
barrier();
if (participateInSorting) {
    dispersePair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);
}
barrier();

// N>64
if (participateInSorting) { flipPair(index, 6); }
barrier();
if (participateInSorting) { dispersePair(index, 5); }
barrier();
if (participateInSorting) { dispersePair(index, 4); }
barrier();
if (participateInSorting) {
    dispersePair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);
}
barrier();

// N>128
if (participateInSorting) { flipPair(index, 7); }
barrier();
if (participateInSorting) { dispersePair(index, 6); }
barrier();
if (participateInSorting) { dispersePair(index, 5); }
barrier();
if (participateInSorting) { dispersePair(index, 4); }
barrier();
if (participateInSorting) {
    dispersePair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);
}
barrier();

// N>256
if (participateInSorting) { flipPair(index, 8); }
barrier();
if (participateInSorting) { dispersePair(index, 7); }
barrier();
if (participateInSorting) { dispersePair(index, 6); }
barrier();
if (participateInSorting) { dispersePair(index, 5); }
barrier();
if (participateInSorting) { dispersePair(index, 4); }
barrier();
if (participateInSorting) {
    dispersePair(index, 3);
    dispersePair(index, 2);
    dispersePair(index, 1);
    dispersePair(index, 0);
}
barrier();

