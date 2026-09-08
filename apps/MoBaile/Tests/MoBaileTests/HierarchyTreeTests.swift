import XCTest
@testable import MoBaile

final class HierarchyTreeTests: XCTestCase {

    private func makeElement(
        id: String = "",
        text: String = "",
        className: String = "android.widget.FrameLayout",
        depth: Int = 0,
        parentIndex: Int? = nil
    ) -> UIElement {
        UIElement(
            tag: className,
            className: className,
            resourceId: id,
            text: text,
            contentDesc: "",
            clickable: false,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            area: 10000,
            package: "com.test",
            platform: .android,
            depth: depth,
            parentIndex: parentIndex
        )
    }

    func testConstroiArvoreComPaiEFilhos() {
        let root = makeElement(id: "root", depth: 0, parentIndex: nil)
        let child1 = makeElement(id: "child1", depth: 1, parentIndex: 0)
        let child2 = makeElement(id: "child2", depth: 1, parentIndex: 0)
        let grandChild = makeElement(id: "grandChild", depth: 2, parentIndex: 1)

        let elements = [root, child1, child2, grandChild]
        let tree = HierarchyTreeView.buildTree(from: elements)

        XCTAssertEqual(tree.count, 1, "Deve haver apenas uma raiz")
        let rootNode = tree[0]
        XCTAssertEqual(rootNode.element.resourceId, "root")
        XCTAssertEqual(rootNode.children?.count, 2, "A raiz deve conter 2 filhos")

        let child1Node = rootNode.children?[0]
        XCTAssertEqual(child1Node?.element.resourceId, "child1")
        XCTAssertEqual(child1Node?.children?.count, 1, "child1 deve conter 1 filho (grandChild)")
        XCTAssertEqual(child1Node?.children?[0].element.resourceId, "grandChild")

        let child2Node = rootNode.children?[1]
        XCTAssertEqual(child2Node?.element.resourceId, "child2")
        XCTAssertNil(child2Node?.children, "Nó folha deve ter children nil para outline correto")
    }

    func testNosRaizMultiplosFicamNoTopo() {
        let rootA = makeElement(id: "rootA", parentIndex: nil)
        let rootB = makeElement(id: "rootB", parentIndex: nil)

        let tree = HierarchyTreeView.buildTree(from: [rootA, rootB])
        XCTAssertEqual(tree.count, 2)
        XCTAssertEqual(tree[0].element.resourceId, "rootA")
        XCTAssertEqual(tree[1].element.resourceId, "rootB")
    }

    func testFiltroDeBuscaPreservaAncestrais() {
        let root = makeElement(id: "root", text: "Container", parentIndex: nil)
        let intermediate = makeElement(id: "box", text: "Painel", parentIndex: 0)
        let target = makeElement(id: "btn_alvo", text: "Comprar Agora", parentIndex: 1)
        let other = makeElement(id: "btn_outro", text: "Cancelar", parentIndex: 1)

        let elements = [root, intermediate, target, other]

        let tree = HierarchyTreeView.buildTree(from: elements, filterText: "Comprar")

        XCTAssertEqual(tree.count, 1, "Raiz deve ser mantida como ancestral")
        let rootNode = tree[0]
        XCTAssertEqual(rootNode.element.resourceId, "root")

        let boxNode = rootNode.children?[0]
        XCTAssertEqual(boxNode?.element.resourceId, "box")
        XCTAssertEqual(boxNode?.children?.count, 1, "Apenas o filho alvo deve estar presente")
        XCTAssertEqual(boxNode?.children?[0].element.resourceId, "btn_alvo")
    }

    func testIndiceInvalidoNaoTravaNemCriaLoop() {
        // Elemento com parentIndex apontando para si mesmo ou fora dos limites
        let selfParent = makeElement(id: "selfParent", parentIndex: 0)
        let outOfBounds = makeElement(id: "outOfBounds", parentIndex: 999)

        let tree = HierarchyTreeView.buildTree(from: [selfParent, outOfBounds])
        XCTAssertEqual(tree.count, 2, "Ambos devem ser promovidos a raízes sem travar em loop")
    }
}
