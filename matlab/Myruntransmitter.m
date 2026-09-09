%% myRunTransmitter.m
% ------------------------------------------------------------------------
% Minimal, WORKING entry point for the CSS PHY floating-point transmitter.
%
% Use this INSTEAD of runMe.m. runMe.m calls CIRselection(), a
% receiver-side function that is not included in this Tx-only package,
% so runMe.m errors out immediately if you try to run it as-is.
%
% ------------------------------------------------------------------------

clc; clear all; close all;

addpath('common');
addpath('transmitter');

%% ---- Global variables the rest of the code expects ----
global chirpIndex samplingFreqMhz carrierFreqGHz codeWordLengthStd
global preambleLengthStd Tchirp Tsub TxDACbitNumber chirpSequenceNumBit_Rx
global payloadLength

%% ---- Choose test parameters (edit these) ----
dataRate      = 0;    % 0 = 1 Mb/s ,  1 = 250 kb/s
payloadLength = 20;   % payload size in bytes (1..127)
chirpIndex    = 1;    % which of the 4 chirp sequences to use (1..4)

%% ---- Populate all the standard tables (Walsh-Hadamard codewords,
%       preamble/SFD, PHR length, etc. -- Section 3.2/3.3 of your spec) ----
globalSettings();

%% ---- Generate the chirp sequence (this call also auto-plots the
%       instantaneous frequency of the 4 subchirps) ----
chirpSequence = chirpSequenceGenerator(chirpIndex, samplingFreqMhz);

%% ---- Build a test payload: random bits, payloadLength bytes ----
rand('state', 0);
incomingStream = round(rand(1, payloadLength * 8));   % 0/1 bit vector

%% ---- Run the full floating-point transmitter chain ----
% (Zero padding -> Demux -> Symbol Mapper -> Interleaver -> Form PPDU ->
%  QPSK Mapper -> DQPSK -> Chirp Modulation, all inside this one call)
TxchirpSequences = ChirpSpreadSpectrum_Tx(incomingStream, dataRate, chirpSequence);

%% ---- Plot the transmitted I/Q waveform ----
figure;
subplot(2,1,1);
plot(real(TxchirpSequences));
title('Transmitted CSS waveform -- Real (I) part');
xlabel('Sample'); ylabel('Amplitude'); grid on;

subplot(2,1,2);
plot(imag(TxchirpSequences));
title('Transmitted CSS waveform -- Imag (Q) part');
xlabel('Sample'); ylabel('Amplitude'); grid on;

%% ---- Quick summary in the Command Window ----
if dataRate == 0
    rateStr = '1 Mb/s';
else
    rateStr = '250 kb/s';
end
fprintf('\n--- Simulation summary ---\n');
fprintf('Data rate            : %s\n', rateStr);
fprintf('Payload length        : %d bytes\n', payloadLength);
fprintf('Chirp sequence index  : %d\n', chirpIndex);
fprintf('Number of Tx samples  : %d\n', length(TxchirpSequences));