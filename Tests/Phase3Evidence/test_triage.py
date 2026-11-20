import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import phase3_triage


def sample():
    return {
        'nodes': [{'id':'app'}, {'id':'file'}, {'id':'global'}],
        'edges': [
            {'id':'E1','source':'app','target':'file','state':'COMPROVADA', 'prerequisites':['signed']},
            {'id':'E2','source':'file','target':'global','state':'NÃO VALIDADA','prerequisites':['consumer']},
        ],
        'capabilities': {'signed': 'available', 'consumer':'unknown'},
        'routes': [{'id':'R1','mechanism':'preferences','target':'global', 'edges':['E1','E2'], 'risk':'low'}],
    }


class TriageTests(unittest.TestCase):
    def test_unproven_consumer_prevents_verified_chain(self):
        result=phase3_triage.triage(sample())
        self.assertEqual(result['routes'][0]['decision'],'UNVERIFIED')
        self.assertEqual(result['routes'][0]['missingCapabilities'],['consumer'])
        self.assertEqual(result['verifiedRouteCount'],0)

    def test_unavailable_capability_blocks_even_proven_edge(self):
        graph=sample()
        graph['edges'][1]['state']='COMPROVADA'
        graph['capabilities']['consumer']='unavailable'
        result=phase3_triage.triage(graph)
        self.assertEqual(result['routes'][0]['decision'],'BLOCKED')

    def test_wrappers_with_same_mechanism_target_and_capabilities_share_group(self):
        graph=sample()
        graph['routes'].append({**graph['routes'][0],'id':'R2'})
        result=phase3_triage.triage(graph)
        self.assertEqual(len(result['equivalentGroups']),1)
        self.assertEqual(result['equivalentGroups'][0],['R1','R2'])

    def test_disconnected_or_undefined_edges_raise(self):
        for mutation in ('disconnected','undefined','duplicate'):
            graph=sample()
            if mutation=='disconnected': graph['edges'][1]['source']='app'
            if mutation=='undefined': graph['routes'][0]['edges']=['missing']
            if mutation=='duplicate': graph['edges'].append(copy.deepcopy(graph['edges'][0]))
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                phase3_triage.triage(graph)

    def test_supported_indirectly_is_not_target_verification(self):
        graph=sample()
        graph['capabilities']['consumer']='available'
        graph['edges'][1]['state']='SUPORTADA INDIRETAMENTE'
        self.assertEqual(phase3_triage.triage(graph)['verifiedRouteCount'],0)


if __name__=='__main__': unittest.main()
