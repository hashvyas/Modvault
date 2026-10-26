'use client';

import React, { useMemo } from 'react';
import {
  ReactFlow,
  Background,
  Controls,
  MarkerType,
  type Node,
  type Edge,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';

export interface DependencyNodeData {
  version_id: string;
  mod_id: string;
  mod_name: string;
  parent_version_id: string | null;
  depth: number;
  dep_type: 'required' | 'optional' | 'recommends' | 'conflicts' | null;
  path: string[];
}

interface Props {
  dependencies: DependencyNodeData[];
}

export function DependencyGraph({ dependencies }: Props) {
  const { nodes, edges } = useMemo(() => {
    if (!dependencies || dependencies.length === 0) {
      return { nodes: [], edges: [] };
    }

    // Group items by depth for hierarchical layout
    const depthGroups: Record<number, DependencyNodeData[]> = {};
    for (const item of dependencies) {
      const d = item.depth ?? 0;
      if (!depthGroups[d]) depthGroups[d] = [];
      depthGroups[d].push(item);
    }

    const flowNodes: Node[] = [];
    const flowEdges: Edge[] = [];
    const seenNodeIds = new Set<string>();

    const DEPTH_X_GAP = 280;
    const NODE_Y_GAP = 100;

    Object.keys(depthGroups)
      .map(Number)
      .sort((a, b) => a - b)
      .forEach((depth) => {
        const items = depthGroups[depth];
        const totalHeight = (items.length - 1) * NODE_Y_GAP;
        const startY = -totalHeight / 2;

        items.forEach((item, index) => {
          const nodeId = item.version_id;
          if (!seenNodeIds.has(nodeId)) {
            seenNodeIds.add(nodeId);

            const isRoot = depth === 0;
            flowNodes.push({
              id: nodeId,
              position: { x: depth * DEPTH_X_GAP, y: startY + index * NODE_Y_GAP },
              data: {
                label: (
                  <div className="text-left font-sans">
                    <div className="font-bold text-xs truncate max-w-[180px]">
                      {item.mod_name}
                    </div>
                    <div className="text-[10px] text-muted-foreground mt-0.5">
                      {isRoot ? 'Target Mod (Root)' : `Depth ${depth}`}
                    </div>
                  </div>
                ),
              },
              style: {
                background: isRoot ? 'rgba(6, 182, 212, 0.15)' : 'rgba(30, 41, 59, 0.8)',
                color: '#f8fafc',
                border: isRoot ? '2px solid #06b6d4' : '1px solid #475569',
                borderRadius: '8px',
                padding: '8px 12px',
                boxShadow: isRoot ? '0 0 12px rgba(6, 182, 212, 0.3)' : 'none',
                minWidth: '160px',
              },
            });
          }

          // Build edge from parent if exists
          if (item.parent_version_id) {
            const edgeId = `e-${item.parent_version_id}-${item.version_id}`;
            const depType = item.dep_type ?? 'required';

            let strokeColor = '#06b6d4';
            let strokeDasharray: string | undefined;

            if (depType === 'optional') {
              strokeColor = '#94a3b8';
              strokeDasharray = '5 5';
            } else if (depType === 'recommends') {
              strokeColor = '#10b981';
              strokeDasharray = '3 3';
            } else if (depType === 'conflicts') {
              strokeColor = '#ef4444';
              strokeDasharray = '4 4';
            }

            flowEdges.push({
              id: edgeId,
              source: item.parent_version_id,
              target: item.version_id,
              label: depType,
              type: 'smoothstep',
              animated: depType === 'required',
              markerEnd: {
                type: MarkerType.ArrowClosed,
                color: strokeColor,
              },
              style: {
                stroke: strokeColor,
                strokeWidth: depType === 'required' ? 2 : 1.5,
                strokeDasharray,
              },
              labelStyle: {
                fill: strokeColor,
                fontWeight: 600,
                fontSize: 10,
              },
              labelBgStyle: {
                fill: '#0f172a',
                fillOpacity: 0.8,
              },
              labelBgPadding: [4, 2],
              labelBgBorderRadius: 4,
            });
          }
        });
      });

    return { nodes: flowNodes, edges: flowEdges };
  }, [dependencies]);

  if (dependencies.length <= 1) {
    return (
      <div className="h-64 flex flex-col items-center justify-center border border-dashed border-border rounded-xl text-center p-6 text-muted-foreground">
        <p className="text-sm font-medium">No downstream dependencies declared for this mod.</p>
        <p className="text-xs mt-1">This mod runs stand-alone or has no dependent mods recorded.</p>
      </div>
    );
  }

  return (
    <div className="h-96 w-full border border-border rounded-xl overflow-hidden bg-card/40">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        fitView
        nodesDraggable={true}
        nodesConnectable={false}
        elementsSelectable={true}
      >
        <Background color="#334155" gap={16} />
        <Controls className="bg-card border-border fill-foreground" />
      </ReactFlow>
    </div>
  );
}
