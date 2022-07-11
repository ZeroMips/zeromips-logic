`default_nettype none

typedef enum logic [4:0] {
	ZM_REFL_LOW     = 5'h00, // (R /W) low reflection register, inverted content in ZM_REFL_HIGH
	ZM_PS2_RXDATA   = 5'h01, // (R) received PS2 data
	ZM_REFL_HIGH    = 5'h1f, // (R /W) high reflection register, inverted content in ZM_REFL_LOW
} zm_reg_t;

module zeromips(
	input clk_i,
	output led_o,

	input [4:0] CPU_ADDR,
	inout [7:0] CPU_DATA,

	input CPU_RWB,
	input CPU_RESB,
	input CPU_IRQB,
	input CPU_CSB,

	inout PS2_CLK,
	inout PS2_DATA,

	output PS2_CLK_,
	output PS2_DATA_,
);

logic bus_out_ena;

logic bus_write_strobe;
logic write_detected;
logic ps2read_toggle;
logic dummy_clk;
logic dummy_data;

logic [7:0] bus_data_out_r; // registered bus_data_out signal, this helps timing
logic [7:0] bus_data_out;

logic [7:0] reg_refl_low;
logic [7:0] reg_ps2_rx;
logic [7:0] reg_refl_high;

assign bus_out_ena  = (!CPU_CSB && CPU_RWB);

assign CPU_DATA = bus_out_ena ? bus_data_out_r : 8'bZ;
assign led_o = 1'b0;

logic [7:0] ps2_rxdata;
logic [7:0] ps2_txdata;
logic ps2_send_req;
logic ps2_busy;
logic ps2_ready;
logic ps2_ready_r;
logic ps2_error;
logic [7:0] ps2_rxdata_fifo;
logic ps2_rxdata_fifo_read;
logic [3:0] ps2_rxdata_fifo_count;
logic [1:0] ps2_rxdata_fifo_level;
logic ps2_rxdata_fifo_empty;
logic ps2_rxdata_fifo_full;

// update registered signals each clock
always_ff @(posedge clk_i) begin
	bus_data_out_r  <= bus_data_out;
	ps2_ready_r <= ps2_ready;
end

ps2_host ps2_host(
	.sys_clk(clk_i),
	.sys_rst(!CPU_RESB),
	.ps2_clk(PS2_CLK),
	.ps2_data(PS2_DATA),

	.tx_data(ps2_txdata),
	.send_req(ps2_send_req),
	.busy(ps2_busy),

	.rx_data(ps2_rxdata),
	.ready(ps2_ready),
	.error(ps2_error)
);

fifo
  #(
    .DEPTH_WIDTH(3),
    .DATA_WIDTH(8)
    )
   ps2_rxfifo
   (
    .clk(clk_i),
    .rst(!CPU_RESB),

    .wr_data_i(ps2_rxdata),
    .wr_en_i(ps2_ready && !ps2_rxdata_fifo_full),

    .rd_data_o(ps2_rxdata_fifo),
    .rd_en_i(ps2_rxdata_fifo_read),

    .full_o(ps2_rxdata_fifo_full),
    .empty_o(ps2_rxdata_fifo_empty)
    );

always_comb begin
	case (CPU_ADDR)
		ZM_REFL_LOW:
			bus_data_out = reg_refl_low;
		ZM_PS2_RXDATA:
			bus_data_out = ps2_rxdata_fifo_count;
		ZM_REFL_HIGH:
			bus_data_out = reg_refl_high;
		default:
			bus_data_out = 8'h42;
	endcase
	PS2_CLK_ = ps2_rxdata_fifo_empty;
	PS2_DATA_ = ps2_rxdata_fifo_full;
end

always_ff @(posedge clk_i) begin
	if (!CPU_RESB) begin
		reg_refl_low <= 8'h55;
		reg_refl_high <= 8'haa;
		reg_ps2_rx <= 8'h11;
		reg_refl_high <= 8'haa;
		write_detected <= 0;
		ps2read_toggle <= 1;
		ps2_send_req <= 0;
		ps2_rxdata_fifo_read <= 0;
	end
	else if (!CPU_CSB && !CPU_RWB) begin
		write_detected = 1;
		case (CPU_ADDR)
			ZM_REFL_LOW:
			begin
				reg_refl_low = CPU_DATA;
				reg_refl_high = ~CPU_DATA;
			end
			ZM_REFL_HIGH:
			begin
				reg_refl_low = ~CPU_DATA;
				reg_refl_high = CPU_DATA;
			end
		endcase
	end
	if (ps2_ready)
		reg_ps2_rx = ps2_rxdata;
end

endmodule

`default_nettype wire // restore default
