%% gen_chirp_roms.m
% =========================================================================
% Generates chirp sequence ROM .mem files for all 4 chirp indices.
%
% Output (8 files, $readmemb compatible binary format):
%   ../rtl/rom/chirp_m1_real.mem   ../rtl/rom/chirp_m1_imag.mem
%   ../rtl/rom/chirp_m2_real.mem   ../rtl/rom/chirp_m2_imag.mem
%   ../rtl/rom/chirp_m3_real.mem   ../rtl/rom/chirp_m3_imag.mem
%   ../rtl/rom/chirp_m4_real.mem   ../rtl/rom/chirp_m4_imag.mem
%
% ROM layout per file — 152 entries (subchirp-major, sample-minor):
%   addr   0 ..  37  →  subchirp k=1, samples n=1..38
%   addr  38 ..  75  →  subchirp k=2, samples n=1..38
%   addr  76 .. 113  →  subchirp k=3, samples n=1..38
%   addr 114 .. 151  →  subchirp k=4, samples n=1..38
%
% Each entry: 6-bit two's complement binary string (signed, range -32..+31)
%
% Quantisation: floor(float_sample * 31)
%   where 31 = 2^(TxDACbitNumber-1) - 1 = 2^5 - 1  (6-bit signed max)
%
% RTL usage:
%   logic signed [5:0] chirp_rom [0:151];
%   initial $readmemb("../rtl/rom/chirp_m1_real.mem", chirp_rom);
%
% NOTE: chirpSequenceGenerator.m has plottingOption hardcoded to 1.
%       This script calls close(gcf) after each call to suppress the plots.
%       If you want to see the instantaneous frequency plots, remove the
%       close(gcf) lines below.
% =========================================================================

addpath('common');

% ── Load global constants (sets Tsub, samplingFreqMhz, TxDACbitNumber) ──
global chirpIndex samplingFreqMhz carrierFreqGHz codeWordLengthStd
global preambleLengthStd Tchirp Tsub TxDACbitNumber chirpSequenceNumBit_Rx
global payloadLength SFD_Std SFDlength PHRlength numBitsPerCodeWordStd
global codeword_1Mbs codeword_250kbs

globalSettings();

% ── Output directory ─────────────────────────────────────────────────────
outDir = fullfile('.', 'rom');
if ~exist(outDir, 'dir')
    mkdir(outDir);
    fprintf('Created directory: %s\n', outDir);
end

% ── Quantisation scale factor ─────────────────────────────────────────────
% 6-bit signed: max positive = 2^5 - 1 = 31
% floor() matches the RTL truncation mode (toward -inf)
BITS   = TxDACbitNumber;          % = 6
SCALE  = 2^(BITS - 1) - 1;       % = 31
MAX_POS =  2^(BITS-1) - 1;       % = +31
MIN_NEG = -2^(BITS-1);           % = -32
NUM_ENTRIES = Tsub * 4;           % = 38 * 4 = 152 entries per ROM

fprintf('=============================================\n');
fprintf('  Chirp ROM Generator\n');
fprintf('  Tsub          = %d samples\n', Tsub);
fprintf('  Subchirps     = 4\n');
fprintf('  Entries/ROM   = %d\n', NUM_ENTRIES);
fprintf('  Bits/entry    = %d (signed two''s complement)\n', BITS);
fprintf('  Scale factor  = %d\n', SCALE);
fprintf('  Output dir    = %s\n', outDir);
fprintf('=============================================\n\n');

% ── Generate ROM files for each chirp index m = 1..4 ─────────────────────
for m = 1:4

    fprintf('Chirp index m=%d ...\n', m);

    % Generate floating-point chirp sequence: Tsub x 4 complex matrix
    % Column k = subchirp k (k=1..4), Row n = sample n (n=1..Tsub)
    chirpSeq_float = chirpSequenceGenerator(m, samplingFreqMhz);
    close(gcf);   % suppress the instantaneous-frequency plot

    % Quantise to 6-bit signed integers: floor(float * 31)
    chirpSeq_fixed = floor(chirpSeq_float * SCALE);

    % ── Sanity check: verify no overflow ─────────────────────────────────
    r_max = max(max(real(chirpSeq_fixed)));
    r_min = min(min(real(chirpSeq_fixed)));
    i_max = max(max(imag(chirpSeq_fixed)));
    i_min = min(min(imag(chirpSeq_fixed)));

    fprintf('  real: [%+d, %+d]   imag: [%+d, %+d]', ...
            r_min, r_max, i_min, i_max);

    if r_max > MAX_POS || r_min < MIN_NEG || ...
       i_max > MAX_POS || i_min < MIN_NEG
        error('OVERFLOW in chirp index %d — values outside [%d, %d]', ...
              m, MIN_NEG, MAX_POS);
    end
    fprintf('   OK\n');

    % ── Open output files ─────────────────────────────────────────────────
    fname_real = fullfile(outDir, sprintf('chirp_m%d_real.mem', m));
    fname_imag = fullfile(outDir, sprintf('chirp_m%d_imag.mem', m));

    fid_re = fopen(fname_real, 'wt');
    fid_im = fopen(fname_imag, 'wt');

    if fid_re == -1 || fid_im == -1
        error('Cannot open output file in %s — check path and permissions', outDir);
    end

    % ── Write header comment (readable by $readmemb, ignored by simulator) 
    fprintf(fid_re, '// chirp_m%d_real.mem\n', m);
    fprintf(fid_re, '// Chirp index m=%d, real part\n', m);
    fprintf(fid_re, '// %d entries, 6-bit two''s complement\n', NUM_ENTRIES);
    fprintf(fid_re, '// addr = k*%d + (n-1),  k=0..3, n=1..%d\n\n', Tsub, Tsub);

    fprintf(fid_im, '// chirp_m%d_imag.mem\n', m);
    fprintf(fid_im, '// Chirp index m=%d, imaginary part\n', m);
    fprintf(fid_im, '// %d entries, 6-bit two''s complement\n', NUM_ENTRIES);
    fprintf(fid_im, '// addr = k*%d + (n-1),  k=0..3, n=1..%d\n\n', Tsub, Tsub);

    % ── Write entries: subchirp-major, sample-minor ───────────────────────
    for k = 1:4
        fprintf(fid_re, '// --- subchirp k=%d ---\n', k);
        fprintf(fid_im, '// --- subchirp k=%d ---\n', k);
        for n = 1:Tsub
            re_val = real(chirpSeq_fixed(n, k));
            im_val = imag(chirpSeq_fixed(n, k));
            fprintf(fid_re, '%s\n', twos_complement(re_val, BITS));
            fprintf(fid_im, '%s\n', twos_complement(im_val, BITS));
        end
    end

    fclose(fid_re);
    fclose(fid_im);
    fprintf('  Written: %s\n', fname_real);
    fprintf('  Written: %s\n\n', fname_imag);
end

fprintf('Done. 8 ROM files written to: %s\n', outDir);


% =========================================================================
% Helper: convert signed integer to N-bit two's complement binary string
% =========================================================================
function s = twos_complement(val, nbits)
    if val < 0
        val = val + 2^nbits;   % two's complement: add 2^N to negative value
    end
    s = dec2bin(val, nbits);   % zero-padded binary string
end
