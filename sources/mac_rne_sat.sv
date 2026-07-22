`timescale 1ns/1ps
//

//
module mac_rne_sat (
    input  logic               clk,
    input  logic               rst,       // synchronous, active-high
    input  logic               en,        // accumulate a*b this cycle
    input  logic               clr,       // clear accumulator this cycle
    input  logic               rd,        // request readout snapshot this cycle
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [15:0] res,       // rounded + saturated snapshot
    output logic               res_valid, // 1-cycle pulse, one cycle after rd
    output logic               ovf        // sticky saturation flag
);




    // 28-bit signed accumulator (spec §3)
    logic signed [27:0] acc;

    // Product, sign-extended to 28 bits before accumulation (spec §3)
    logic signed [15:0] p;
    logic signed [27:0] p_ext;

    assign p     = a * b;
    assign p_ext = {{12{p[15]}}, p};

    // --- Combinational rounding/saturation of the *current* (pre-update)
    // accumulator value. This is the value acc holds going into this edge,
    // i.e. the snapshot for a readout requested this cycle (spec §4). ---
    logic signed [20:0] q;        // floor(acc/256) via arithmetic shift, +headroom for +1
    logic        [7:0]  r;        // remainder, 0..255 (unsigned low byte)
    logic signed [20:0] rounded;
    logic signed [15:0] sat_val;
    logic                sat_flag;

    assign q = {{1{acc[27]}}, acc[27:8]};  // arithmetic right shift by 8 == floor(acc/256)
    assign r = acc[7:0];                    // remainder in [0,255], correct even for negatives

    always_comb begin
        if (r < 8'd128)
            rounded = q;
        else if (r > 8'd128)
            rounded = q + 21'sd1;
        else begin
            // tie: round to even
            if (q[0] == 1'b0)
                rounded = q;             // q even -> stays
            else
                rounded = q + 21'sd1;    // q odd -> rounds up
        end

        // Saturation applied AFTER rounding (spec §4)
        if (rounded > 21'sd32767) begin
            sat_val  = 16'sd32767;
            sat_flag = 1'b1;
        end else if (rounded < -21'sd32768) begin
            sat_val  = -16'sd32768;
            sat_flag = 1'b1;
        end else begin
            sat_val  = rounded[15:0];
            sat_flag = 1'b0;
        end
    end

    // --- Sequential logic ---
    always_ff @(posedge clk) begin
        if (rst) begin
            acc       <= 28'sd0;
            res       <= 16'sd0;
            res_valid <= 1'b0;
            ovf       <= 1'b0;
        end else begin

            // Readout path (spec §4/§5): uses acc's pre-update value via
            // sat_val/sat_flag computed above (non-blocking reads of acc
            // below still see the old value, so this is naturally the
            // "before this cycle's update" snapshot).
            if (rd) begin
                res       <= sat_val;
                res_valid <= 1'b1;
                if (sat_flag)
                    ovf <= 1'b1;         // set wins on same-cycle clr+saturate
                else if (clr)
                    ovf <= 1'b0;
                // else: ovf holds (non-saturating readout leaves it unchanged)
            end else begin
                res_valid <= 1'b0;
                if (clr)
                    ovf <= 1'b0;
                // else: ovf holds; res also holds (no assignment here)
            end

            // Accumulator update (spec §3 table), clr/en combination.
            case ({clr, en})
                2'b00: acc <= acc;
                2'b01: acc <= acc + p_ext;
                2'b10: acc <= 28'sd0;
                2'b11: acc <= p_ext;
            endcase
        end
    end

endmodule

