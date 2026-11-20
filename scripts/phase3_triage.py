#!/usr/bin/env python3
"""Validate evidence routes and group equivalent prerequisites. Runs entirely offline."""
import argparse
import json
from collections import defaultdict
from pathlib import Path

STATES = {'COMPROVADA', 'SUPORTADA INDIRETAMENTE', 'NÃO VALIDADA', 'CONTRADITA', 'BLOQUEADA'}


def _indexed(items):
    result = {item['id']: item for item in items}
    if len(result) != len(items):
        raise ValueError('IDs duplicados no grafo.')
    return result


def triage(graph):
    nodes = _indexed(graph['nodes'])
    edges = _indexed(graph['edges'])
    routes = _indexed(graph['routes'])
    capabilities = graph['capabilities']
    if any(state not in {'available', 'unavailable', 'unknown'} for state in capabilities.values()):
        raise ValueError('Estado de capacidade inválido.')
    for edge in edges.values():
        if edge['source'] not in nodes or edge['target'] not in nodes or edge['state'] not in STATES:
            raise ValueError('Aresta sem nó ou com estado inválido.')
        if set(edge['prerequisites']) - capabilities.keys():
            raise ValueError('Capacidade sem definição.')

    groups = defaultdict(list)
    evaluated = []
    for route in routes.values():
        try:
            chain = [edges[ref] for ref in route['edges']]
        except KeyError as error:
            raise ValueError('Referência de aresta inexistente.') from error
        if not chain or any(a['target'] != b['source'] for a, b in zip(chain, chain[1:])):
            raise ValueError('Rota desconectada.')
        if chain[-1]['target'] != route['target']:
            raise ValueError('A rota termina em um alvo diferente do declarado.')
        required = sorted({cap for edge in chain for cap in edge['prerequisites']})
        missing = [cap for cap in required if capabilities[cap] != 'available']
        blocked = any(capabilities[cap] == 'unavailable' for cap in missing)
        states = {edge['state'] for edge in chain}
        if blocked or states.intersection({'BLOQUEADA', 'CONTRADITA'}):
            decision = 'BLOCKED'
        elif missing or states != {'COMPROVADA'}:
            decision = 'UNVERIFIED'
        else:
            decision = 'VERIFIED_WITHIN_SCOPE'
        # Scope is the route's declared target. Observation can pass without proving global change.
        evaluated.append({'id': route['id'], 'target': route['target'], 'decision': decision,
                          'missingCapabilities': missing, 'risk': route['risk']})
        groups[(route['mechanism'], route['target'], tuple(required))].append(route['id'])
    verified = sum(item['decision'] == 'VERIFIED_WITHIN_SCOPE' for item in evaluated)
    return {'routes': evaluated, 'verifiedRouteCount': verified,
            'verifiedGlobalRoutes': sum(item['target'] == 'global' and item['decision'] == 'VERIFIED_WITHIN_SCOPE'
                                        for item in evaluated),
            'equivalentGroups': sorted([group for group in groups.values() if len(group) > 1])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('graph', type=Path)
    args = parser.parse_args()
    try:
        result = triage(json.loads(args.graph.read_text(encoding='utf-8')))
    except (KeyError, ValueError, OSError) as error:
        parser.exit(2, f'Grafo inválido: {error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
