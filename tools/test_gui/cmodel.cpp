#include "cmodel.h"

#include <cstdio>

#define CONFIG_URI "http://www.nic.cz/ns/router/uci-raw"

class ConfigModel::Elem {
public:
	virtual ~Elem() {}
};

class ConfigModel::Section : public Elem {
public:
	Section(const QDomElement &sectionElement) :
		name(sectionElement.namedItem("name").toElement().text()),
		type(sectionElement.namedItem("type").toElement().text()),
		anonymous(!sectionElement.namedItem("anonymous").isNull())
	{}
	const QString name, type;
	const bool anonymous;
};

class ConfigModel::ConfigFile : public Elem {
public:
	ConfigFile(const QDomElement &configElement, const ConfigModel *model, int order) :
		name(configElement.namedItem("name").toElement().text()),
		index(model->createIndex(order, 0, this))
	{
		printf("Created config file %s\n", name.toLocal8Bit().data());
		const QDomNodeList &sectionElements(configElement.elementsByTagNameNS(CONFIG_URI, "section"));
		for (int i = 0; i < sectionElements.count(); i ++)
			sections << new Section(sectionElements.at(i).toElement());
	}
	const QString name;
	QList<Section *> sections;
	const QModelIndex index;
};

ConfigModel::ConfigModel(const QDomDocument &configData_) :
	configData(configData_)
{
	// The namespace trick doesn't neem to work for some reason. OK, whatever.
	const QDomNodeList &configElements(configData.documentElement().elementsByTagNameNS(CONFIG_URI, "config"));
	for (int i = 0; i < configElements.count(); i ++)
		configs << new ConfigFile(configElements.at(i).toElement(), this, i);
}

QModelIndex ConfigModel::index(int row, int column, const QModelIndex &parent) const {
	printf("index %d %d\n", row, column);
	return configs[row]->index;
}

QModelIndex ConfigModel::parent(const QModelIndex &index) const {
	printf("parent\n");
	return QModelIndex();
}

int ConfigModel::rowCount(const QModelIndex &parent) const {
	printf("rowcount\n");
	return configs.size();
}

int ConfigModel::columnCount(const QModelIndex &parent) const {
	printf("colmncount\n");
	return 1;
}

QVariant ConfigModel::data(const QModelIndex &index, int role) const {
	switch (role) {
		case Qt::DisplayRole:
			printf("Data\n");
			return configs[index.row()]->name;
		default:
			printf("Other\n");
			return QVariant();
	}
}
