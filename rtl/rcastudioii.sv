//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module rcastudioii
(
	input              clk_sys,
  input              clk_cpu,
	input              reset,
	
  input wire         ioctl_download,
  input wire   [7:0] ioctl_index,
  input wire         ioctl_wr,
  input       [24:0] ioctl_addr,
	input        [7:0] ioctl_dout,

  input       [10:0] ps2_key,
	input  reg         ce_pix,

	output reg         HBlank,
	output reg         HSync,
	output reg         VBlank,
	output reg         VSync,
  output reg         video_de,
	output       [7:0] video
);

////////////////// VIDEO //////////////////////////////////////////////////////////////////

wire        Disp_On;
wire        Disp_Off;
reg  [1:0]  SC = 2'b10;
reg  [7:0]  video_din;

wire   INT;
wire   DMAO;
wire   EFx;
wire   Locked;

wire vram_rd;
pixie_dp pixie_dp (
    // front end, CDP1802 bus clock domain
    .clk(clk_sys),        // I
    .reset(reset),        // I
    .clk_enable(ce_pix),  // I      

    .SC(SC),              // I [1:0]
    .disp_on(io_n[0]),    // I
    .disp_off(~io_n[0]),  // I 

    .data_addr(),         // O [9:0]
    .data_rd(vram_rd),    // O    
    .data_in(video_din),  // I [7:0]    

    .DMAO(DMAO),          // O
    .INT(INT),            // O
    .EFx(EFx),            // O

    // back end, video clock domain
    .video_clk(clk),      // I
    .csync(),             // O
    .video(video),        // O

    .VSync(VSync),        // O
    .HSync(HSync),        // O
    .VBlank(VBlank),      // O
    .HBlank(HBlank),      // O
    .video_de(video_de)   // O    
);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

reg [7:0] btnKP1 = 'hff;
reg [7:0] btnKP2 = 'hff;

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btnKP1  <= 'd1; // 12'b000000000010; // Keypad1 1
			'h1E: btnKP1  <= 'd2; // 12'b000000000100; // Keypad1 2
      'h26: btnKP1  <= 'd3; // 12'b000000001000; // Keypad1 3
      'h25: btnKP1  <= 'd4; // 12'b000000010000; // Keypad1 4
      'h2E: btnKP1  <= 'd5; // 12'b000000100000; // Keypad1 5
      'h36: btnKP1  <= 'd6; // 12'b000001000000; // Keypad1 6
      'h3D: btnKP1  <= 'd7; // 12'b000010000000; // Keypad1 7
      'h3E: btnKP1  <= 'd8; // 12'b000100000000; // Keypad1 8
      'h46: btnKP1  <= 'd9; // 12'b001000000000; // Keypad1 9
      'h45: btnKP1  <= 'd0; // 12'b000000000001; // Keypad1 0
      default: btnKP1 <= 'hff; // Keypad1
		endcase
	end
end

////////////////// CPU //////////////////////////////////////////////////////////////////

reg  [3:0] EF = 4'b1111;
// 0111  EF4 Key pressed on keypad 2
// 1011  EF3 Key pressed on keypad 1
// 1101  EF2 not connected
// 1110  EF1 Video display monitoring, driven by EFx from 1861
always @(posedge clk_sys) begin
    if ((btnKP1 != 'hff) && pressed)
      EF <= 4'b1011;
    else if ((btnKP2 != 'hff) && pressed)
      EF <= 4'b0111;    
    else if (~EFx)
      EF <= 4'b1110;
    else
      EF <= 4'b1111;
end

reg [7:0] cpu_din;
reg [7:0] cpu_dout;
wire Q;
wire unsupported;
wire [2:0] io_n;
wire io_inp;
wire io_out;

reg [15:0] cpu_ram_addr;
reg  [7:0] cpu_ram_din;
reg  [7:0] cpu_ram_dout;

cdp1802 cdp1802 (
  .clock    (clk_sys),
  .resetq   (~reset),

  .Q        (Q),        // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF       (EF),       // I 3:0 external flags EF1 to EF4

  .io_din   (cpu_din),     
  .io_dout  (cpu_dout),    
  .io_n     (io_n),     // O 2:0 IO control lines: N2,N1,N0  (N0 used for display on/off)
  .io_inp   (io_inp),   // O IO input signal
  .io_out   (io_out),   // O IO output signal

  .unsupported(unsupported),

  .ram_rd (ram_rd),       // O
  .ram_wr (ram_wr),       // O
  .ram_a  (cpu_ram_addr), // O
  .ram_q  (DI),           // I
  .ram_d  (cpu_ram_dout)  // O
);

////////////////// RAM //////////////////////////////////////////////////////////////////

reg ram_cs;

reg          ram_rd; // RAM read enable
reg          ram_wr; // RAM write enable
reg   [7:0]  ram_d;  // RAM write data

wire  [7:0]   romDo_StudioII;
wire [11:0]   romA;

rom #(.AW(11), .FN("../rom/studio2.hex")) Rom_StudioII
(
	.clock      (clk_sys        ),
	.ce         (1'b1           ),
	.data_out   (romDo_StudioII ),
	.a          (romA[10:0]     )
);

dpram #(.ADDR(12)) dpram (
  .clk    (clk_sys),        // I

	.a_ce   (ram_rd),         // I
	.a_wr   (ram_wr),         // I
	.a_din  (DI),             // I
	.a_dout (dpram_dout),     // O
	.a_addr (AB),       // I

	.b_ce   (ioctl_download), // I
	.b_wr   (ioctl_wr),       // I
	.b_din  (ioctl_dout),     // I
	.b_dout (),               // O
	.b_addr ((ioctl_index==0) ? ioctl_addr : (16'h0400 + ioctl_addr)) // I
);

////////////////// DMA //////////////////////////////////////////////////////////////////

//0000-02FF	ROM 	      RCA System ROM : Interpreter
//0300-03FF	ROM	        RCA System ROM : Always present
//0400-07FF	ROM	        Games Programs, built in (no cartridge)
//0400-07FF	Cartridge	  Cartridge Games (when cartridge plugged in)
//0800-08FF	RAM	        System Memory, Program Memory etc.
//0900-09FF	RAM	        Display Memory
//0A00-0BFF	Cartridge	  (MultiCart) Available for Cartridge games if required, probably isn't.
//0C00-0DFF	RAM/ROM	    Duplicate of 800-9FF - the RAM is double mapped in the default set up. 
//                      This RAM can be disabled and ROM can be put here instead, 
//                      so assume this is ROM for emulation purposes.
//0E00-0FFF	Cartridge	  (MultiCart) Available for Cartridge games if required, probably isn't.

wire rom_cs   = AB ==? 16'b0000_00xx_xxxx_xxxx;
wire cart_cs  = AB ==? 16'b0000_01xx_xxxx_xxxx; 
wire pram_cs  = AB ==? 16'b0000_1000_xxxx_xxxx; 
wire vram_cs  = AB ==? 16'b0000_1001_xxxx_xxxx; 
wire mcart_cs = AB ==? 16'b0000_101x_xxxx_xxxx; 

reg  [15:0] vram_addr;
wire [15:0] AB = dma_busy ? dma_addr : cpu_ram_addr;
wire  [7:0] DO = dma_busy ? dma_dout : cpu_ram_dout;
wire pram_we = pram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;
wire vram_we = vram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;

always @(negedge clk_sys) begin
  DI <= rom_cs   ? cpu_ram_dout :
        cart_cs  ? cpu_ram_dout :
        pram_cs  ? cpu_ram_dout :
        vram_cs  ? cpu_ram_dout :        
        mcart_cs ? cpu_ram_dout : 
        8'hff;     
end

always @(negedge clk_sys) begin
  if (vram_cs && ram_wr) begin
    video_din <= cpu_ram_dout;
   // $display("cpu_ram_dout %x ram_a %x video_din %x", cpu_ram_dout, ram_a, video_din);
  end 
end

// internal games still there if (0x402==2'hd1 && 0x403==2'h0e && 0x404==2'hd2 && 0x405==2'h39)
// 0x40e = game 1
// 0x439 = game 2
// 0x48b = game 3
// 0x48d = game 4
// 0x48f = game 5

wire        dma_rdy = DMAO;
reg         dma_ctrl = 1'b1;
reg  [15:0] dma_addr;
reg   [7:0] DI;
wire  [7:0] dma_dout;
reg   [7:0] dma_length = 8'b1;

dma dma(
  .clk(clk_sys),
  .rdy(dma_rdy),
  .ctrl(dma_ctrl),
  .src_addr(cpu_ram_addr),
  .dst_addr(cpu_ram_addr),
  .addr(dma_addr), // => to AB
  .din(DI),
  .dout(dma_dout),
  .length(dma_length),
  .busy(dma_busy),
  .sel(dma_sel),
  .write(dma_write)
);

/////////////////////////////////////////////////////////////////////////////////////////

endmodule
