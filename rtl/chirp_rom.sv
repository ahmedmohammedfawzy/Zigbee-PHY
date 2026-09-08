module chirp_rom #(
  parameter string M1_REAL = "../rtl/rom/chirp_m1_real.mem",
  parameter string M1_IMAG = "../rtl/rom/chirp_m1_imag.mem",
  parameter string M2_REAL = "../rtl/rom/chirp_m2_real.mem",
  parameter string M2_IMAG = "../rtl/rom/chirp_m2_imag.mem",
  parameter string M3_REAL = "../rtl/rom/chirp_m3_real.mem",
  parameter string M3_IMAG = "../rtl/rom/chirp_m3_imag.mem",
  parameter string M4_REAL = "../rtl/rom/chirp_m4_real.mem",
  parameter string M4_IMAG = "../rtl/rom/chirp_m4_imag.mem",

  parameter integer CHIRP_INDEX = 1
) (
  input  logic [7:0] addr,
  output logic signed [5:0] chirp_real,
  output logic signed [5:0] chirp_imag
);
  logic signed [5:0] mr [0:151];
  logic signed [5:0] mi [0:151];

  initial begin
      case (CHIRP_INDEX)
        1: begin
          $readmemb(M1_REAL, mr);
          $readmemb(M1_IMAG, mi);
        end
        2: begin
          $readmemb(M2_REAL, mr);
          $readmemb(M2_IMAG, mi);
        end
        3: begin
          $readmemb(M3_REAL, mr);
          $readmemb(M3_IMAG, mi);
        end
        4: begin
          $readmemb(M4_REAL, mr);
          $readmemb(M4_IMAG, mi);
        end
        default: begin
          $readmemb(M1_REAL, mr);
          $readmemb(M1_IMAG, mi);
        end
      endcase
    end

  always_comb begin
    chirp_real = 6'sd0;
    chirp_imag = 6'sd0;

    if (addr < 8'd152) begin
        chirp_real = mr[addr];
        chirp_imag = mi[addr];
    end
  end
endmodule
