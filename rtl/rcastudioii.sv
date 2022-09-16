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

wire        INT;
wire        DMAO;
wire        EFx;
wire        Locked;

reg         vram_rd;
//reg         vram_ack;

pixie_video pixie_video (
    // front end, CDP1802 bus clock domain
    .clk        (clk_sys),    // I
    .reset      (reset),      // I
    .clk_enable (ce_pix),     // I      

    .SC         (SC),         // I [1:0]
    .disp_on    (io_n[0]),    // I
    .disp_off   (~io_n[0]),   // I 

    .data_addr  (vram_addr),  // O [9:0]
    .data_in    (video_din),  // I [7:0]    

    .DMAO       (DMAO),       // O
    .INT        (INT),        // O
    .EFx        (EFx),        // O

    // back end, video clock domain
    .video_clk  (clk_sys),    // I
    .csync      (),           // O
    .video      (video),      // O

    .VSync      (VSync),      // O
    .HSync      (HSync),      // O
    .VBlank     (VBlank),     // O
    .HBlank     (HBlank),     // O
    .video_de   (video_de)    // O    
);

////////////////// KEYPAD //////////////////////////////////////////////////////////////////

reg  [3:0] btnKP1  = 4'b1111;
reg  [3:0] btnKP2  = 4'b1111;
wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btnKP1  <= 4'b0001; // 12'b000000000010; // Keypad1 1     0001
			'h1E: btnKP1  <= 4'b0010; // 12'b000000000100; // Keypad1 2     0010
      'h26: btnKP1  <= 4'b0011; // 12'b000000001000; // Keypad1 3     0011
      'h25: btnKP1  <= 4'b0100; // 12'b000000010000; // Keypad1 4     0100
      'h2E: btnKP1  <= 4'b0101; // 12'b000000100000; // Keypad1 5     0101
      'h36: btnKP1  <= 4'b0110; // 12'b000001000000; // Keypad1 6     0110
      'h3D: btnKP1  <= 4'b0111; // 12'b000010000000; // Keypad1 7     0111
      'h3E: btnKP1  <= 4'b1000; // 12'b000100000000; // Keypad1 8     1000
      'h46: btnKP1  <= 4'b1001; // 12'b001000000000; // Keypad1 9     1001
      'h45: btnKP1  <= 4'b0000; // 12'b000000000001; // Keypad1 0     0000

			'h15: btnKP2  <= 4'b0001; // 12'b000000000010; // Keypad2 Q     0001
			'h1D: btnKP2  <= 4'b0010; // 12'b000000000100; // Keypad2 W     0010
      'h24: btnKP2  <= 4'b0011; // 12'b000000001000; // Keypad2 E     0011
      'h2D: btnKP2  <= 4'b0100; // 12'b000000010000; // Keypad2 R     0100
      'h2C: btnKP2  <= 4'b0101; // 12'b000000100000; // Keypad2 T     0101
      'h35: btnKP2  <= 4'b0110; // 12'b000001000000; // Keypad2 Y     0110
      'h3C: btnKP2  <= 4'b0111; // 12'b000010000000; // Keypad2 U     0111
      'h43: btnKP2  <= 4'b1000; // 12'b000100000000; // Keypad2 I     1000
      'h44: btnKP2  <= 4'b1001; // 12'b001000000000; // Keypad2 O     1001
      'h4D: btnKP2  <= 4'b0000; // 12'b000000000001; // Keypad2 P     0000 
      //default: begin
      //  btnKP1 <= 'hff; // Keypad1
      //  btnKP2 <= 'hff; // Keypad1        
      //end
		endcase
	end
  else begin
    btnKP1 <= 4'b0000; // Keypad1
    btnKP2 <= 4'b0000; // Keypad2
  end
end

////////////////// CPU //////////////////////////////////////////////////////////////////

reg  [3:0] EF = 4'b0000;
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

/*
always @(posedge clk_sys) begin
  if(EFx==0) 
    EF <= 4'b0110;
  else
  //  EF <= 4'b0000;
  if(io_n[1]==0) begin
    if ((btnKP1 == cpu_dout[3:0]) && pressed) begin
      EF <= EF | 4'b1000;
      $display("btnKP1 cpu_dout[3:0] = %b  %d EF %b", cpu_dout[3:0], cpu_dout[3:0], EF);      
    end
    else if ((btnKP2 == cpu_dout[3:0]) && pressed) begin
      EF <= EF | 4'b0001;    
      $display("btnKP2 cpu_dout[3:0] = %b  %d EF %b", cpu_dout[3:0], cpu_dout[3:0], EF);
    end
    //else begin
    //  EF <= EF & 4'b0001;
    //end
  end      
end
*/

reg  [7:0] cpu_din;
reg  [7:0] cpu_dout;
wire       Q;
wire       unsupported;
wire [2:0] io_n;
wire       io_inp;
wire       io_out;

reg [15:0] cpu_ram_addr;
reg  [7:0] cpu_ram_din;
reg  [7:0] cpu_ram_dout;

reg WAIT_N      = 1'b0;
reg INT_N       = 1'b0;
reg dma_in_req  = 1'b0;
reg dma_out_req = 1'b0;

cdp1802 cdp1802 (
  .CLOCK        (clk_sys),
  .CLEAR_N      (~reset),

  .Q            (Q),            // O external pin Q Turns the sound off and on. When logic '1', the beeper is on.
  .EF           (EF),           // I 3:0 external flags EF1 to EF4

  .WAIT_N       (wait_req),
  .INT_N        (INT_N),
  .dma_in_req   (dma_in_req),
  .dma_out_req  (dma_out_req),
  .SC           (SC),

  .io_din       (cpu_din),     
  .io_dout      (cpu_dout),    
  .io_n         (io_n),         // O 2:0 IO control lines: N2,N1,N0  (N0 used for display on/off)
  .io_inp       (io_inp),       // O IO input signal
  .io_out       (io_out),       // O IO output signal

  .unsupported  (unsupported),

  .ram_rd       (ram_rd),       // O
  .ram_wr       (ram_wr),       // O
  .ram_a        (ram_a),        // O cpu_ram_addr
  .ram_q        (ram_q),        // I DI
  .ram_d        (ram_d)         // O cpu_ram_dout
);

/*
cosmac cosmac (
   .clk         (clk_sys),     // I
   .clk_enable  (1'b1),        // I
   .clear       (~reset),      // I
   .dma_in_req  (dma_in_req),  // I
   .dma_out_req (dma_out_req), // I
   .int_req     (INT_N),       // I
   .wait_req    (wait_req),    // I
   .ef          (EF),          // I [4:1]
   .data_in     (ram_q),       // I [7:0]
   .data_out    (ram_d),       // O [7:0]
   .address     (ram_a),       // O [15:0]
   .mem_read    (ram_rd),      // O
   .mem_write   (ram_wr),      // O
   .io_port     (io_n),        // O [2:0]
   .q_out       (Q),           // O
   .sc          (SC)           // O [1:0]
);
*/

////////////////// RAM //////////////////////////////////////////////////////////////////

reg          ram_cs;
reg          ram_rd; // RAM read enable
reg          ram_wr; // RAM write enable
reg   [7:0]  ram_d;  // RAM write data
reg  [15:0]  ram_a;  // RAM address
reg   [7:0]  ram_q;  // RAM read data

/*
wire  [7:0]  romDo_StudioII;
wire [11:0]  romA;

rom #(.AW(11), .FN("../rom/studio2.hex")) Rom_StudioII
(
	.clock      (clk_sys        ),
	.ce         (1'b1           ),
	.data_out   (romDo_StudioII ),
	.a          (romA[10:0]     )
);
*/////////
dpram #(.addr_width_g(12)) dpram (
  .clk_sys    (clk_sys),        // I

	.ram_cs     (ram_rd),         // I
	.ram_we     (ram_wr),         // I
	.ram_d      (ram_d),          // I DI
	.ram_q      (ram_q),          // O dpram_dout
	.ram_ad     (ram_a),          // I AB

	.ram_cs_b   (portb_ce),       // I
	.ram_we_b   (portb_wr),       // I
	.ram_d_b    (portb_din),      // I
	.ram_q_b    (portb_dout),     // O
	.ram_ad_b   (portb_addr)      // I
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

/*
wire rom_cs   = ram_a ==? 16'b0000_00xx_xxxx_xxxx;
wire cart_cs  = ram_a ==? 16'b0000_01xx_xxxx_xxxx; 
wire pram_cs  = ram_a ==? 16'b0000_1000_xxxx_xxxx; 
wire vram_cs  = ram_a ==? 16'b0000_1001_xxxx_xxxx; 
wire mcart_cs = ram_a ==? 16'b0000_101x_xxxx_xxxx; 
*/

reg  [15:0] vram_addr;
//wire [15:0] AB = dma_busy ? dma_addr : ram_a;
//wire  [7:0] DO = dma_busy ? dma_dout : ram_d;
//wire pram_we = pram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;
//wire vram_we = vram_cs ? dma_busy ? ~dma_write : ~ram_wr : 1'b1;

/*
always @(negedge clk_sys) begin
  DI <= rom_cs   ? ram_d :
        cart_cs  ? ram_d :
        pram_cs  ? ram_d :
        vram_cs  ? ram_d :        
        mcart_cs ? ram_d : 
        8'hff;     
end
*/

reg        portb_ce;
reg        portb_wr;
reg  [7:0] portb_din;
reg  [7:0] portb_dout;
reg [15:0] portb_addr;
always @(posedge clk_sys) begin
  portb_ce  <= 1'b0;
  portb_wr  <= 1'b0;
  if(ioctl_download) begin
    portb_ce   <= ioctl_download;
    portb_wr   <= ioctl_wr;
    portb_din  <= ioctl_dout;
    portb_addr <= ioctl_index==0 ? ioctl_addr : (16'h0400 + ioctl_addr);
  end
  else if(vram_addr >= 'h0900) begin
    portb_ce   <= 1'b1;
    portb_addr <= vram_addr;
    video_din <= portb_dout;        
  end
end

// internal games still there if (0x402==2'hd1 && 0x403==2'h0e && 0x404==2'hd2 && 0x405==2'h39)
// 0x40e = game 1
// 0x439 = game 2
// 0x48b = game 3
// 0x48d = game 4
// 0x48f = game 5
/*
wire        dma_rdy = DMAO;
reg         dma_ctrl = 1'b1;
reg  [15:0] dma_addr;
reg   [7:0] DI;
wire  [7:0] dma_dout;
reg   [7:0] dma_length = 8'b1;

dma dma (
  .clk      (clk_sys),      // I
  .rdy      (dma_rdy),      // I
  .ctrl     (dma_ctrl),     // I
  .src_addr (ram_a),        // I 15:0
  .dst_addr (ram_a),        // I 15:0
  .addr     (dma_addr),     // O 15:0 => to AB
  .din      (DI),           // I 7:0
  .dout     (dma_dout),     // I 7:0
  .length   (dma_length),   // I
  .busy     (dma_busy),     // O
  .sel      (dma_sel),      // O
  .write    (dma_write)     // O
);
*/
/////////////////////////////////////////////////////////////////////////////////////////

endmodule
