#include "config.h"
#include "cmodel.h"

#include <QProcess>
#include <QtXml>

#include <cassert>
#include <cstdio>

#define MARK "]]>]]>"
const QString netconfUri("urn:ietf:params:xml:ns:netconf:base:1.0");

Config::Config() :
	process(NULL)
{
	setupUi(this);
}

void Config::on_connectButton_clicked() {
	if (process) {
		disconnectNuci();
	} else {
		connectNuci();
	}
}

void Config::connectNuci() {
	incoming.clear();
	rpcCallbacks.clear();
	// Create and connect the process
	process = new QProcess(this);
	connect(process, SIGNAL(readyReadStandardOutput()), this, SLOT(data()));
	connect(process, SIGNAL(finished(int, QProcess::ExitStatus)), this, SLOT(terminated()));
	process->start(commandEdit->text());
	// Let it start
	process->waitForStarted(-1);
	// Push the <hello> message there.
	sendData("<?xml version='1.0' encoding='UTF-8'?><hello xmlns='urn:ietf:params:xml:ns:netconf:base:1.0'><capabilities><capability>urn:ietf:params:netconf:base:1.0</capability></capabilities></hello>");
	connectButton->setEnabled(false);
	connectButton->setText("Disconnect");
}

void Config::disconnectNuci() {
	sendRpc("<close-session/>");
	process->closeWriteChannel();
	connectButton->setEnabled(false);
	downloadButton->setEnabled(false);
}

void Config::data() {
	// Some data arrived from remote
	incoming += process->readAll();
	int index;
	while ((index = incoming.indexOf(MARK)) != -1) {
		// Extract the message and drop it from the front
		QByteArray message(incoming.data(), index);
		incoming.remove(0, index + strlen(MARK));
		printf("Received XML:\n%s\n\n", message.data());

		handleMessage(message);
	}
}

void Config::terminated() {
	connectButton->setEnabled(true);
	connectButton->setText("Connect");
	process->deleteLater();
	process = NULL;
}

void Config::sendData(const QString &data) {
	QByteArray cp(data.toLocal8Bit());
	printf("Sending XML message:\n%s\n\n", cp.data());
	cp.append("\n" MARK);
	while (!cp.isEmpty())
		writeData(cp);
}

void Config::writeData(QByteArray &array) {
	qint64 written = process->write(array);
	assert(written > 0);
	array.remove(0, written);
}

void Config::handleMessage(const QByteArray &message) {
	QDomDocument xml;
	bool ok = xml.setContent(message, true);
	assert(ok);
	/*
	 * We don't check the namespace here. Qt seems to return empty string
	 * (I must be doing something wrong, obviously), and this is dirty
	 * test tool only anyway.
	 */
	const QString &name(xml.documentElement().tagName());
	if (name == "hello") {
		handleHello(xml);
		return;
	} else if (name == "rpc-reply") {
		handleRpc(xml);
		return;
	}
	assert(false);
}

void Config::handleRpc(const QDomDocument &rpc) {
	QString sid(rpc.documentElement().attribute("message-id"));
	bool ok = true;
	size_t id = sid.toULongLong(&ok);
	assert(ok);
	if (rpcCallbacks.contains(id)) {
		(this->*rpcCallbacks[id])(rpc, id);
		rpcCallbacks.remove(id);
	}
}

void Config::handleHello(const QDomDocument &) {
	connectButton->setEnabled(true);
	downloadButton->setEnabled(true);
	downloadButton->click();
}

size_t Config::sendRpc(const QString &xml, RpcCallback callback) {
	static size_t id = 0;
	sendData(QString("<?xml version='1.0' encoding='UTF-8'?><rpc xmlns='urn:ietf:params:xml:ns:netconf:base:1.0' message-id='%1'>%2</rpc>").arg(++id).arg(xml));
	if (callback) {
		rpcCallbacks[id] = callback;
	}
	return id;
}

void Config::on_downloadButton_clicked() {
	sendRpc("<get-config><source><running/></source></get-config>", &Config::configDownloaded);
}

void Config::configDownloaded(const QDomDocument &rpc, size_t) {
	printf("Configuration downloaded\n");
	// FIXME: This leaks
	model = new ConfigModel(rpc);
	configView->setModel(model);
	on_configView_clicked();
}

void Config::on_configView_clicked() {
	editWidget->setEnabled(process && configView->currentIndex().isValid());
}

void Config::on_removeButton_clicked() {
	prepareXml("remove", false, false);
}

void Config::on_replaceButton_clicked() {
	prepareXml("replace", true, true);
}

void Config::on_mergeButton_clicked() {
	prepareXml("merge", false, true);
}

void Config::on_createButton_clicked() {

}

void Config::prepareXml(const QString &operation, bool subnodes, bool content) {
	QDomDocument doc;
	doc.setContent(QString("<edit-config><target><running/></target><config><uci xmlns='http://www.nic.cz/ns/router/uci-raw'/></config></edit-config>"));
	QDomElement node(model->getNode(configView->currentIndex(), doc, subnodes, content));
	node.setAttribute("xmlns:nc", netconfUri);
	node.setAttribute("nc:operation", operation);
	xmlEdit->setText(doc.toString(4));
}
