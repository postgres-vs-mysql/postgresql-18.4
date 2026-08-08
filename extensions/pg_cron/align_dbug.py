#!/usr/bin/env python3
import sys
import re
import os

def align_dbug_print(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()
    
    modified = False
    i = 0
    while i < len(lines):
        line = lines[i]
        # 匹配 DBUG_PRINT 行
        if re.match(r'^\s*DBUG_PRINT\s*\(', line):
            old_indent = re.match(r'^\s*', line).group()
            
            # 向下找第一个非空、非DBUG_、非注释的C语句
            target_indent = None
            for j in range(i + 1, len(lines)):
                nl = lines[j].strip()
                if not nl:
                    continue
                if nl.startswith('//') or nl.startswith('/*'):
                    continue
                if nl.startswith('DBUG_'):
                    continue
                # 找到目标行，提取缩进
                target_indent = re.match(r'^\s*', lines[j]).group()
                break
            
            # 如果向下没找到，向上找
            if target_indent is None:
                for j in range(i - 1, -1, -1):
                    pl = lines[j].strip()
                    if not pl:
                        continue
                    if pl.startswith('//') or pl.startswith('/*'):
                        continue
                    if pl.startswith('DBUG_'):
                        continue
                    target_indent = re.match(r'^\s*', lines[j]).group()
                    break
            
            # 应用新缩进
            if target_indent and target_indent != old_indent:
                lines[i] = target_indent + line.lstrip()
                modified = True
                print(f"  {filepath}:{i+1} 缩进已对齐")
        
        i += 1
    
    if modified:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        return True
    return False

# 处理所有C/H文件
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith(('.c', '.h')):
            filepath = os.path.join(root, file)
            if align_dbug_print(filepath):
                print(f"✓ 已处理: {filepath}")
