%% css_verify_golden.m
% Bit-exact MATLAB golden reference for the CSS PHY transmitter RTL.
% Mirrors tx_controller.sv + qpsk_mapper.sv + dqpsk_encoder.sv +
% csk_modulator.sv exactly, using the SAME .mem ROM files the RTL reads.
clear; clc;

%% ---- Test case (edit these) ----
rate       = 0;                 % 0 = 1 Mbps, 1 = 250 kbps
chirpIndex = 1;                 % 1..4  (must match CHIRP_INDEX param in tx_top)
payload    = uint8(0:19);       % PSDU bytes as written into payload_ram, 0..127 bytes

%% ---- ROM paths: point these at rtl/roms/ from your unzipped project ----
romDir = fullfile('..','rtl','roms');   % adjust to your actual path
chirpReal = readMemSigned(fullfile(romDir, sprintf('chirp_m%d_real.mem',chirpIndex)),6);
chirpImag = readMemSigned(fullfile(romDir, sprintf('chirp_m%d_imag.mem',chirpIndex)),6);
cw250     = readMem32(fullfile(romDir,'codeword_250k.mem'));      % 64x32 logical
cw1m      = [1 1 1 1;1 0 1 0;1 1 0 0;1 0 0 1;0 0 0 0;0 1 0 1;0 0 1 1;0 1 1 0]; % symbol_mapper_1m.sv

%% ---- Step 1: PHR (phr_generator.sv) ----
L = double(numel(payload));
phr = zeros(1,12);
phr(1:7) = bitget(uint8(L),1:7);   % LSB-first, bits 8-12 stay 0

%% ---- Step 2: zero padding (zero_padder.sv) ----
N = rate*24 + (1-rate)*6;
baseBits = 12 + L*8;
padBits  = mod(-baseBits, N); if padBits==0, padBits = N; end
totalPairs = (baseBits + padBits)/2;

%% ---- Step 3: split framed stream into I/Q pair streams (pair-source mux) ----
Ibits = zeros(1,totalPairs); Qbits = zeros(1,totalPairs);
for pidx = 0:totalPairs-1
    if pidx < 6
        Ibits(pidx+1) = phr(pidx*2+1); Qbits(pidx+1) = phr(pidx*2+2);
    elseif pidx < 6 + L*4
        ppi = pidx - 6;
        byteIdx = floor(ppi/4) + 1;
        bitSel  = mod(ppi,4)*2;
        byteBits = bitget(payload(byteIdx),1:8);      % LSB-first
        Ibits(pidx+1) = byteBits(bitSel+1); Qbits(pidx+1) = byteBits(bitSel+2);
    end   % else: padding, stays 0
end

%% ---- Step 4: symbol mapping (+ interleaver for 250k) ----
if rate == 0
    nSym = totalPairs/3; chipI = []; chipQ = [];
    for s = 0:nSym-1
        vI = bits2val(Ibits(s*3+1:s*3+3),3); vQ = bits2val(Qbits(s*3+1:s*3+3),3);
        chipI = [chipI, cw1m(vI+1,:)]; chipQ = [chipQ, cw1m(vQ+1,:)]; %#ok<AGROW>
    end
else
    nGrp = totalPairs/12; chipI = []; chipQ = [];
    for g = 0:nGrp-1
        b = g*12;
        vA_I=bits2val(Ibits(b+1:b+6),6);  vA_Q=bits2val(Qbits(b+1:b+6),6);
        vB_I=bits2val(Ibits(b+7:b+12),6); vB_Q=bits2val(Qbits(b+7:b+12),6);
        inI = [cw250(vB_I+1,:), cw250(vA_I+1,:)];   % {B,A}, matches inter_i_in
        inQ = [cw250(vB_Q+1,:), cw250(vA_Q+1,:)];
        chipI = [chipI, interleave64(inI)]; chipQ = [chipQ, interleave64(inQ)]; %#ok<AGROW>
    end
end

%% ---- Step 5: prepend preamble + SFD (preamble_sfd_rom.sv) ----
if rate == 0
    sfd = bitget(uint16(bin2dec('0111010010011100')),16:-1:1);
    sync = [ones(1,32), sfd];
else
    sfd = bitget(uint16(bin2dec('0111101000100011')),16:-1:1);
    sync = [ones(1,80), sfd];
end
chipI = [sync, chipI]; chipQ = [sync, chipQ];
chipI = double(chipI); chipQ = double(chipQ);

%% ---- Step 6: QPSK phase mapping (qpsk_mapper.sv) ----
delta = zeros(1,numel(chipI));
for k = 1:numel(chipI)
    key = 2*double(chipI(k)) + double(chipQ(k));
    switch key
        case 3, delta(k)=0; case 1, delta(k)=1; case 0, delta(k)=2; case 2, delta(k)=3;
    end
end

%% ---- Step 7: DQPSK phase-index accumulation (dqpsk_encoder.sv) ----
nPh = numel(delta);
Sfull = zeros(1,nPh+4);
for n = 1:nPh, Sfull(4+n) = mod(Sfull(n) + delta(n), 4); end
S = Sfull(5:end);

%% ---- Step 8: group into 4s, rotate chirp, insert gaps (csk_modulator.sv) ----
gapEven = containers.Map({1,2,3,4}, {10,20,30,40});
gapOdd  = containers.Map({1,2,3,4}, {70,60,50,40});
nGroups = numel(S)/4;
TxReal = []; TxImag = [];
for g = 0:nGroups-1
    p = S(g*4+1 : g*4+4);              % [p0 p1 p2 p3], chronological
    gRe = zeros(1,152); gIm = zeros(1,152);
    for k = 0:3
        idx = (k*38+1):(k*38+38);
        re = double(chirpReal(idx)); im = double(chirpImag(idx));
        switch p(k+1)
            case 0, or_=re-im; oi_=re+im;
            case 1, or_=-re-im; oi_=re-im;
            case 2, or_=-re+im; oi_=-re-im;
            case 3, or_=re+im; oi_=-re+im;
        end
        gRe(idx) = or_; gIm(idx) = oi_;
    end
    isOdd = mod(g,2)==1;   % group 0 = even, matches gp_odd trace
    gapLen = isOdd*gapOdd(chirpIndex) + (~isOdd)*gapEven(chirpIndex);
    TxReal = [TxReal, gRe, zeros(1,gapLen)]; %#ok<AGROW>
    TxImag = [TxImag, gIm, zeros(1,gapLen)]; %#ok<AGROW>
end

fprintf('Golden model produced %d samples.\n', numel(TxReal));

%% ---- Step 9: write for diffing against the RTL testbench dump ----
writematrix([TxReal(:) TxImag(:)], 'golden_tx_iq.csv');

%% ==================== helper functions ====================
function v = readMemSigned(fname, nbits)
    lines = readlines(fname); lines = lines(~startsWith(strtrim(lines),"//") & strtrim(lines)~="");
    v = int32(zeros(numel(lines),1));
    for i=1:numel(lines)
        u = bin2dec(char(lines(i)));
        if bitget(u,nbits), u = u - 2^nbits; end   % two's complement
        v(i) = u;
    end
end
function rom = readMem32(fname)
    lines = readlines(fname); lines = lines(~startsWith(strtrim(lines),"//") & strtrim(lines)~="");
    bits = char(strjoin(lines,'')); bits = bits - '0';
    rom = reshape(bits, 32, [])';   % 64x32, row r = codeword for symbol r-1
end
function val = bits2val(b, n) %#ok<INUSD>
    val = 0; for i=1:numel(b), val = val*2 + b(i); end
end
function outSeq = interleave64(inSeq)
    inV = fliplr(inSeq); outV = zeros(1,64); m = interleaverMap();
    for v=0:63, outV(v+1) = inV(m(v+1)+1); end
    outSeq = fliplr(outV);
end
function m = interleaverMap()
    pairs=[63 63;62 62;61 61;60 60;59 11;58 10;57 9;56 8;55 55;54 54;53 53;52 52; ...
        51 3;50 2;49 1;48 0;47 47;46 46;45 45;44 44;43 27;42 26;41 25;40 24; ...
        39 39;38 38;37 37;36 36;35 19;34 18;33 17;32 16;31 31;30 30;29 29;28 28; ...
        27 43;26 42;25 41;24 40;23 23;22 22;21 21;20 20;19 35;18 34;17 33;16 32; ...
        15 15;14 14;13 13;12 12;11 59;10 58;9 57;8 56;7 7;6 6;5 5;4 4; ...
        3 51;2 50;1 49;0 48];
    m = zeros(1,64); for i=1:64, m(pairs(i,1)+1)=pairs(i,2); end
end