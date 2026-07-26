`timescale 1ns/1ps
//
// mac_rne_sat -- implement per doc/spec.md.
// Do not change the module name, port list, or port directions.
// Synthesizable SystemVerilog only (Icarus Verilog, -g2012). No SVA.
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

    // TODO: implement the accumulate / readout / overflow logic per
    // doc/spec.md. The tie-offs below only keep the skeleton compiling;
    // replace them with your implementation.
    assign res       = '0;
    assign res_valid = 1'b0;
    assign ovf       = 1'b0;

endmodule
